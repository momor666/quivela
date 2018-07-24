// Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// 
// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.
// A copy of the License is located at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// or in the "license" file accompanying this file. This file is distributed 
// on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
// express or implied. See the License for the specific language governing 
// permissions and limitations under the License.

include "Lang.dfy"
include "Indistinguishable.dfy"

/* Here we're trying to prove under what side conditions commonly used transformation steps are sound.
   At the moment, this is very incomplete, since we first need to establish a number of other properties
   about the language. Note that the "assume false" statements here do not impact soundness as
   this file is not included anywhere for now. */

predicate ListAll<T>(pred: T -> bool, xs: List<T>) {
  match xs
    case LNil => true
    case Cons(x, xs') => pred(x) && ListAll(pred, xs')
}

// FIXME: reduce duplication in the following few functions:
predicate method UnusedInList(name: Var, es: List<Expr>)
  decreases es
{
  match es
    case LNil => true
    case Cons(e, es') => UnusedIn(name, e) && UnusedInList(name, es')
}

predicate method UnusedInInits(name: Var, inits: List<Init>)
  decreases inits
{
  match inits
    case LNil => true
    case Cons(init, inits') => init.name != name && UnusedIn(name, init.val) &&
      UnusedInInits(name, inits')

}

/* This is a probably bit more conservative than necessary in that the new name
   must also not be used as a  name, etc. */
predicate method UnusedIn(name: Var, e: Expr)
  decreases e
{
  match e
    case EVar(x) => x != name
    case ENop() => true
    case EITE(cond, thn, els) => UnusedIn(name, cond) && UnusedIn(name, thn) && UnusedIn(name, els)
    case ECall(cobj, cname, cargs) => UnusedIn(name, cobj) && UnusedInList(name, cargs) &&
      cname != name
    case EAssign(lhs, rhs) => UnusedIn(name, lhs) && UnusedIn(name, rhs)
    case ENew(inits, body) => UnusedInInits(name, inits) && UnusedIn(name, body)
    case EConst(val) => true
    case ETuple(vals) => UnusedInList(name, vals)
    case ESeq(e1, e2) => UnusedIn(name, e1) && UnusedIn(name, e2)
    case ECVar (obj, name', idx) =>
      UnusedIn(name, obj) && UnusedIn(name, idx) &&
      // We'll need to refine the following, since it's only sound if the object doesn't
      // obtain a reference to itself in another variable
      (obj != EConst(Nil) || name' != name)
    case EMethod(name', args, body) => !InList(args, name) && name' != name && UnusedIn(name, body)
}

// More convenient wrapper for all the preconditions on method equivalence
predicate MethodEquivalencePreqs(ctx1: Context, ctx2: Context, addr1: Value, addr2: Value, Inv: ContextEquivalence,
  objs1: ObjList, objs2: ObjList, m: Var, values: List<Value>) {
    HavocPrecondition(ctx1, ctx2, addr1, addr2, Inv, objs1, objs2) &&
    Inv(ctx1, ctx2, addr1.addr, addr2.addr) &&
    ValidMethod(ctx1, addr1.addr, m) && ValidMethod(ctx2, addr2.addr, m) &&
    Length(GetMethod(ctx1, addr1.addr, m).args) == Length(GetMethod(ctx2, addr2.addr, m).args) &&
    Length(values) == Length(GetMethod(ctx1, addr1.addr, m).args)
}

predicate AssocListLe<K, V>(xs: List<Pair<K, V>>, ys: List<Pair<K, V>>) {
  match xs
    case LNil => true
    case Cons(p, xs') => AssocGet(ys, p.car).Some? && AssocListLe(xs', ys)
}

lemma {:induction body} ENewReturnsValidRef(ctxp: Context, fields: List<Init>, body: Expr)
  ensures
  var (addr1, ctx1) := Eval(ENew(fields, body), ctxp, FUEL);
  addr1.Ref? && ValidRef(addr1.addr, ctx1)
{
  var (addr1, ctx1) := Eval(ENew(fields, body), ctxp, FUEL);
  assert addr1.Ref?;
  assume false; // FIXME
}



type AList<K, V> = List<Pair<K, V>>

function method Filter<T>(pred: T -> bool, xs: List<T>): List<T>
ensures ListAll(pred, Filter(pred, xs))
{
  match xs
  case LNil => LNil
  case Cons(x, xs') => if pred(x) then Cons(x, Filter(pred, xs')) else Filter(pred, xs')
}

lemma {:induction xs} RemoveKeyRemoves<K(==), V>(k: K, xs: List<Pair<K, V>>)
  ensures 
  var res := Filter((p: Pair<K, V>) => p.car != k, xs);
  AssocGet(res, k).None? && Length(res) <= Length(xs)
{ }

function method RemoveKey<K(==), V>(k: K, xs: List<Pair<K, V>>): AList<K, V>
  ensures AssocGet(RemoveKey(k, xs), k).None? && Length(RemoveKey(k, xs)) <= Length(xs)
{
  RemoveKeyRemoves(k, xs);
  Filter((p: Pair<K, V>) => p.car != k, xs)
}


// If ys agrees with xs on all keys present in xs, then ys extends xs.
predicate AssocExtended<K, V>(xs: List<Pair<K, V>>, ys: List<Pair<K,V>>) 
  decreases Length(xs)
{
  match xs
  case LNil() => true
  case Cons(p, xs') => AssocGet(ys, p.car) == Some(p.cdr) && AssocExtended(RemoveKey(p.car, xs'), ys)
}

lemma AssocExtendedTest()
ensures  AssocExtended(Cons(Pair(1, 2), Cons(Pair(1, 3), Cons(Pair(2, 4), LNil))),
                       Cons(Pair(2, 4), Cons(Pair(1, 2), Cons(Pair(3, 5), LNil))))
{}

predicate ExtendedContext(ctx: Context, ctx': Context) 
{
  AssocExtended(ctx.objs, ctx'.objs) &&
  AssocExtended(ctx.methods, ctx'.methods)
}

lemma {:induction xs} AssocExtendedReflAux<K, V>(xs: AList<K, V>)
  ensures xs.LNil? || (xs.Cons? && AssocExtended(RemoveKey(xs.car.car, xs.cdr), xs))
{
  assume false; // FIXME 
}

lemma AssocExtendedRefl<K, V>(xs: AList<K, V>)
  ensures AssocExtended(xs, xs)
{
  match xs {
    case LNil => { 

    }
    case Cons(p, xs') => {
      assert AssocGet(xs, p.car) == Some(p.cdr);
      assert AssocExtended(RemoveKey(p.car, xs'), xs) by {
        AssocExtendedReflAux(xs);
      }
    }
  }
}

lemma ExtendedContextRefl(ctx: Context)
  ensures ExtendedContext(ctx, ctx)
{
  AssocExtendedRefl(ctx.objs);
  AssocExtendedRefl(ctx.methods);
}

// An expression e has no external effects if it does not modify existing objects in a context, though it may create new ones
predicate NoExternalEffects(e: Expr) {
  forall ctx: Context, fuel: Fuel ::
    var (res, ctx') := Eval(e, ctx, fuel);
    ExtendedContext(ctx, ctx')
}

lemma New_NoExternalEffects() 
ensures NoExternalEffects(ENew(LNil(), ENop()))
{
  forall ctx: Context, fuel: Fuel
  ensures ExtendedContext(ctx, Eval(ENew(LNil(), ENop()), ctx, fuel).1)
  {
    var (res, ctx') := Eval(ENew(LNil(), ENop()), ctx, fuel);
    if fuel > 0 {
      assert ctx' == ctx by {assume false;}
      assert ExtendedContext(ctx, ctx') by {ExtendedContextRefl(ctx);}
    } else {
      assert ctx' == ctx;
      assert ExtendedContext(ctx, ctx') by {ExtendedContextRefl(ctx);}
    }
  }
}

predicate ValidContext(ctx: Context) {
  ctx.ths < ctx.nextAddr &&
  forall k: Addr | k >= ctx.nextAddr :: 
    AssocGet(ctx.objs, k).None? && AssocGet(ctx.methods, k).None?
}

lemma ExtendedContext_AssocSet(ctx: Context, addr: Addr, obj: Object)
  requires ValidContext(ctx) && addr < ctx.nextAddr
  ensures ValidContext(ctx.(objs := AssocSet(ctx.objs, addr, obj)))
{

}

lemma EvalTupleElts_ThisUnchanged(exprs: List<Expr>, ctx: Context, fuel: Fuel)
ensures EvalTupleElts(exprs, ctx, fuel).1.ths == ctx.ths
decreases fuel, exprs
{
  match exprs {
    case LNil => {

    }
    case Cons(e, exprs') => {
      var (val, newCtx) := Eval(e, ctx, fuel);
      var (cdr, ctx') := EvalTupleElts(exprs', newCtx, fuel);
      calc {
        EvalTupleElts(exprs, ctx, fuel).1;
        EvalTupleElts(exprs', newCtx, fuel).1;
      }
      assert newCtx.ths == ctx.ths by { Eval_ThisUnchanged(e, ctx, fuel); }
      assert ctx'.ths == newCtx.ths by { EvalTupleElts_ThisUnchanged(exprs', newCtx, fuel); }
    }
  }
}

lemma InitLocals_ThisUnchanged(locals: List<Init>, ctx: Context, fuel: Fuel, acc: Env)
  decreases fuel, locals
  ensures InitLocals(locals, ctx, fuel, acc).car.ths == ctx.ths
{
  var res := InitLocals(locals, ctx, fuel, acc);
  match locals {
    case LNil => {
      assert res == Pair(ctx, acc);
    }
    case Cons(local, locals') => {
      var l := locals.car;
      var oldScope := ctx.scope;
      var ctx_ := ctx.(scope := Append(acc, oldScope));
      if l.val == EConst(Nil()) {
        var (ret, ctx') := Eval_Var(EVar(l.name), ctx_, fuel);
        InitLocals_ThisUnchanged(locals', ctx'.(scope := oldScope), fuel, AssocSet(acc, l.name, ret));
        // InitLocals(locals.cdr, ctx'.(scope := oldScope), fuel, AssocSet(acc, l.name, ret))
      } else {
        var (eval, ctx') := Eval(l.val, ctx_, fuel);
        Eval_ThisUnchanged(l.val, ctx_, fuel);
        InitLocals_ThisUnchanged(locals', ctx'.(scope := oldScope), fuel, AssocSet(acc, l.name, eval));
        // InitLocals(locals.cdr, ctx'.(scope := oldScope), fuel, AssocSet(acc, l.name, eval))
      }
    }
  } 
}

lemma EvalNew_ThisUnchanged(e: Expr, ctx: Context, fuel: Fuel)
  decreases fuel
  requires e.ENew?
  ensures Eval_New(e, ctx, fuel).1.ths == ctx.ths  
{
  var locals := e.locals; var body := e.body;
  var ret := InitLocals(e.locals, ctx, fuel, LNil);
  var ctx' := ret.car; var vlocals := ret.cdr;
  var oldThs := ctx'.ths;
  var oldScope := ctx'.scope;
  var addr := ctx'.nextAddr;
  var immuts := Find_Immutables(e.locals);
  var ctx'' := ctx'.(objs := AssocSet(ctx'.objs, addr, Object(vlocals, immuts)), methods := AssocSet(ctx'.methods, addr, LNil), nextAddr := ctx'.nextAddr + 1, ths := addr);
  var (ret', ctx''') := Eval(e.body, ctx'', fuel);
  // (Ref(addr), ctx'''.(ths := oldThs, scope := oldScope))
  calc {
    Eval_New(e, ctx, fuel).1.ths;
    ctx'''.(ths := oldThs, scope := oldScope).ths;
    oldThs;
    ctx'.ths;
    == { InitLocals_ThisUnchanged(e.locals, ctx, fuel, LNil); }
    ctx.ths;
  }
}

lemma EvalArgs_ThisUnchanged(names: List<Var>, exprs: List<Expr>, ctx: Context, fuel: Fuel, acc: Scope)
  requires Length(names) == Length(exprs)
  ensures EvalArgs(names, exprs, ctx, fuel, acc).1.ths == ctx.ths
{
  assume false;
}

lemma CallWithScope_ThisUnchanged(body: Expr, ctx: Context, scope: Scope, ths: Addr, fuel: Fuel)
  decreases fuel
  ensures Call_With_Scope(body, ctx, scope, ths, fuel).1.ths == ctx.ths
{
}

lemma Eval_ThisUnchanged(e: Expr, ctx: Context, fuel: Fuel)
  ensures Eval(e, ctx, fuel).1.ths == ctx.ths
  decreases fuel, e
{
  if fuel == 0 {
  } else {
    match e
    case EVar(x) => { }
    case ENop() => { }
    case EConst(i) => { }
    case ETuple(es) => { 
      calc { 
        Eval(e, ctx, fuel).1;
        Eval_Tuple(e, ctx, fuel-1).1;
        EvalTupleElts(e.vals, ctx, fuel-1).1;
      }
      EvalTupleElts_ThisUnchanged(e.vals, ctx, fuel-1);
    }
    case ESeq(e1, e2) => {
      var (res1, ctx1) := Eval(e1, ctx, fuel-1);
      var (res2, ctx2) := Eval(e2, ctx1, fuel-1);
      calc {
        Eval(e, ctx, fuel);
        Eval_Seq(e, ctx, fuel-1);
        (res2, ctx2);
      } 
      Eval_ThisUnchanged(e1, ctx, fuel-1);
      Eval_ThisUnchanged(e2, ctx1, fuel-1);
    }
    case ECVar(obj, n, idx) => {
      var (vobj, ctx') := Eval(obj, ctx, fuel-1);
      Eval_ThisUnchanged(obj, ctx, fuel-1); 
      Eval_ThisUnchanged(idx, ctx', fuel-1);
    }
    case EMethod(methName, args, methBody) => { }
    case ECall(obj, name, args) => { 
      var (eref, ctx') := Eval(obj, ctx, fuel-1);
      Eval_ThisUnchanged(obj, ctx, fuel-1);
      if eref.Ref? {
        if ValidRef(eref.addr, ctx') && AssocGet(AssocGet(ctx'.methods, eref.addr).val, name).Some? {
          var mtd := AssocGet(AssocGet(ctx'.methods, eref.addr).val, name).val;
          if Length(mtd.args) != Length(args) {
          } else {
            var (scope, ctx'') := EvalArgs(mtd.args, args, ctx', fuel-1, LNil);
            EvalArgs_ThisUnchanged(mtd.args, args, ctx', fuel-1, LNil);
            CallWithScope_ThisUnchanged(mtd.body, ctx'', scope, eref.addr, fuel-1);
          }
        } else {}
      } else if eref.Nil? {
        if Is_Builtin_Arity(name) != -1 {
          assume false;
        } else {
          var baseAddr := if ValidRef(ctx'.ths, ctx') && AssocGet(AssocGet(ctx'.methods, ctx'.ths).val, name).Some? then ctx'.ths else 0;
          if ValidRef(baseAddr, ctx') && AssocGet(AssocGet(ctx'.methods, baseAddr).val, name).Some? {
            var mtd := AssocGet(AssocGet(ctx'.methods, baseAddr).val, name).val;
            if Length(mtd.args) != Length(args) {
            } else {
              var (scope, ctx'') := EvalArgs(mtd.args, args, ctx', fuel-1, LNil);
              EvalArgs_ThisUnchanged(mtd.args, args, ctx', fuel-1, LNil);
              CallWithScope_ThisUnchanged(mtd.body, ctx'', scope, baseAddr, fuel-1);
            }
          } else {}
        }
      } else {}
    }
    case EITE(cond, thn, els) => {
      var (econd, ctx') := Eval(cond, ctx, fuel-1);
      calc {
        Eval(e, ctx, fuel);
        Eval_ITE(e, ctx, fuel-1);
      }
      Eval_ThisUnchanged(cond, ctx, fuel-1);
      Eval_ThisUnchanged(els, ctx', fuel-1);
      Eval_ThisUnchanged(thn, ctx', fuel-1);
    }
    case EAssign(lhs, rhs) => { 
      calc {
        Eval(e, ctx, fuel);
        Eval_Assign(e, ctx, fuel-1);
      }
      var (erhs, ctx') := Eval(rhs, ctx, fuel-1);
      Eval_ThisUnchanged(rhs, ctx, fuel-1);
      if lhs.EVar? {
      } else if lhs.ECVar? {
        var (eobj, ctx'') := Eval(lhs.obj, ctx', fuel-1);
        var (eidx, ctx''') := Eval(lhs.idx, ctx'', fuel-1);
        Eval_ThisUnchanged(lhs.obj, ctx', fuel-1);
        Eval_ThisUnchanged(lhs.idx, ctx'', fuel-1);
      } else {
      }
    }
    case ENew(inits, newBody) => { 
      calc {
        Eval(e, ctx, fuel);
        Eval_New(e, ctx, fuel-1);
      }
      EvalNew_ThisUnchanged(e, ctx, fuel-1);
    }
  }
}

lemma EvalTupleElts_PreservesValidContext(es: List<Expr>, ctx: Context, fuel: Fuel)
  decreases fuel, es
  requires ValidContext(ctx)
  ensures ValidContext(EvalTupleElts(es, ctx, fuel).1)
{
  match es {
    case LNil => {

    }
    case Cons(e, es') => {
      var (val, newCtx) := Eval(e, ctx, fuel);
      Eval_PreservesValidContext(e, ctx, fuel);
      EvalTupleElts_PreservesValidContext(es', newCtx, fuel);
    }
  }
}

lemma Eval_PreservesValidContext(e: Expr, ctx: Context, fuel: Fuel)
  decreases fuel, e
  requires ValidContext(ctx)
  ensures 
    var (ret, ctx') := Eval(e, ctx, fuel);
    ValidContext(ctx')
{
  var (res, ctxRet) := Eval(e, ctx, fuel);
  if (fuel == 0) {
    assert ctxRet == ctx;
  } else {
    match e {
        case EVar(x) => { }
        case ENop() => { }
        case EConst(i) => { }
        case ETuple(es) => { 
          var (elts, ctx1) := EvalTupleElts(e.vals, ctx, fuel-1);
          EvalTupleElts_PreservesValidContext(e.vals, ctx, fuel-1);
          calc {
            Eval(e, ctx, fuel).1;
            Eval_Tuple(e, ctx, fuel-1).1;
            ctx1;
          }
          assert ValidContext(ctx1);
        }
        case ESeq(e1, e2) => { 
          // Eval_PreservesValidContext(ctx, e1, fuel-1);
          var (v1, ctx1) := Eval(e1, ctx, fuel-1);
          var (v2, ctx2) := Eval(e2, ctx1, fuel-1);
          calc {
            (res, ctxRet);
            Eval_Seq(e, ctx, fuel-1);
            (v2, ctx2);
          }
          assert ValidContext(ctx1) by { Eval_PreservesValidContext(e1, ctx, fuel-1); }
          assert ValidContext(ctx2) by { Eval_PreservesValidContext(e2, ctx1, fuel-1); }
        }
        case ECVar(obj, n, idx) => { assume false; }
        case EMethod(methName, args, methBody) => { assume false; }
        case ECall(cobj, cname, cargs) => { assume false; }
        case EITE(cond, thn, els) => { 
          var (econd, ctx1) := Eval(cond, ctx, fuel-1);
          assert ValidContext(ctx1) by { Eval_PreservesValidContext(cond, ctx, fuel-1); }
          assert (res, ctxRet) == Eval_ITE(e, ctx, fuel-1);
          if econd.Error? || econd.Nil? || (econd.Int? && econd.val == 0) {
            assert ctxRet == Eval(els, ctx1, fuel-1).1;
            Eval_PreservesValidContext(els, ctx1, fuel-1);
          } else {
            assert ctxRet == Eval(thn, ctx1, fuel-1).1;
            Eval_PreservesValidContext(thn, ctx1, fuel-1);
          }
        }
        case EAssign(lhs, rhs) => {
          var (erhs, ctx') := Eval(rhs, ctx, fuel-1);
          Eval_PreservesValidContext(rhs, ctx, fuel-1);
          Eval_ThisUnchanged(rhs, ctx, fuel-1);
          if lhs.EVar? {
            assume false;
          } else if lhs.ECVar? {
            var (eobj, ctx'') := Eval(lhs.obj, ctx', fuel-1);
            var (eidx, ctx''') := Eval(lhs.idx, ctx'', fuel-1);
            Eval_PreservesValidContext(lhs.obj, ctx', fuel-1);
            Eval_PreservesValidContext(lhs.idx, ctx'', fuel-1);
            assume false;
          } else { }
        }
        case ENew(inits, newBody) => { assume false; }
    }
  }
}

lemma {:induction fields} InitLocalsAppend(fields: List<Init>, fields2: List<Init>, ctx: Context, fuel: Fuel, acc: Env)
  ensures
    var ret := InitLocals(fields, ctx, fuel, acc);
    var ret' := InitLocals(Append(fields, fields2), ctx, fuel, acc);
    ret' == InitLocals(fields2, ret.car, fuel, ret.cdr)
{
  assume false; // FIXME
}

predicate {:induction false} Equivalent_Method'(ctx1: Context, ctx2: Context, addr1: Value, addr2: Value, m: Var, Inv: ContextEquivalence) {
  addr1.Ref? && addr2.Ref? && 
       ValidRef(addr1.addr, ctx1) && ValidRef(addr2.addr, ctx2) &&
       ValidMethod(ctx1, addr1.addr, m) && ValidMethod(ctx2, addr2.addr, m) &&
       Length(GetMethod(ctx1, addr1.addr, m).args) == Length(GetMethod(ctx2, addr2.addr, m).args) &&
       Inv(ctx1, ctx2, addr1.addr, addr2.addr) &&
  forall values: List<Value>, objs1: ObjList, objs2: ObjList |
      Length(GetMethod(ctx1, addr1.addr, m).args) == Length(values) &&
      HavocPrecondition(ctx1, ctx2, addr1, addr2, Inv, objs1, objs2) ::
      HavocPostcondition(m, values, ctx1, ctx2, addr1, addr2, Inv, objs1, objs2)
}

// If we evaluate something and there's no error, then if we evaluate it in a new context with
// some new objects, it should give the same result as before.
// This is hopefully true since the language only allows you to hold references to existing objects.
lemma {:induction e} EvalExtend(ctx: Context, ctx': Context, e: Expr, fuel: Fuel, res'': Value)
  requires ValidContext(ctx) && ValidContext(ctx') && ExtendedContext(ctx, ctx') && Eval(e, ctx, fuel).0 == res'' && res'' != Error()
  ensures Eval(e, ctx', fuel).0 == res''
{
  assume false;
}

lemma UnusedIn_Eval(e: Expr, ctx: Context, fuel: Fuel, x: Var, v: Value)
  requires
    AssocGet(ctx.objs, ctx.ths).Some? &&
    UnusedIn(x, e) &&
    Eval(e, ctx, fuel).0 != Error()
  ensures
    var thsObj := AssocGet(ctx.objs, ctx.ths).val;
    var ctx' := ctx.(objs := AssocSet(ctx.objs, ctx.ths, thsObj.(locals := AssocSet(thsObj.locals, x, v))));
    Eval(e, ctx, fuel) == Eval(e, ctx', fuel)
{
  match e
  case EVar(x) => { assume false; }
  case ENop() => { assume false; }
  case EConst(i) => { assume false; }
  case ETuple(es) => { assume false; }
  case ESeq(e1, e2) => { assume false; }
  case ECVar(obj, n, idx) => { assume false; }
  case EMethod(methName, args, methBody) => { assume false; }
  case ECall(cobj, cname, cargs) => { assume false; }
  case EITE(cond, thn, els) => { assume false; }
  case EAssign(lhs, rhs) => { assume false; }
  case ENew(inits, newBody) => { assume false; }
}

predicate NoRawRefsList(es: List<Expr>)
{
  match es
    case LNil => true
    case Cons(e, es') => NoRawRefs(e) && NoRawRefsList(es')
}

predicate NoRawRefsInits(inits: List<Init>)
{
  match inits
    case LNil => true
    case Cons(init, inits') => NoRawRefs(init.val) && NoRawRefsInits(inits')
}


predicate NoRawRefs(e: Expr)
{
  match e
    case EVar(x) => true
    case EConst(v) => !v.Ref?
    case ETuple(es) => NoRawRefsList(es)
    case ENop() => true
    case ESeq(e1, e2) => NoRawRefs(e1) && NoRawRefs(e2)
    case ECVar(obj, n, idx) => NoRawRefs(obj) && NoRawRefs(idx)
    case EMethod(methName, args, methBody) => NoRawRefs(methBody)
    case ECall(cobj, cname, cargs) => NoRawRefs(cobj) && NoRawRefsList(cargs)
    case EITE(cond, thn, els) => NoRawRefs(cond) && NoRawRefs(thn) && NoRawRefs(els)
    case EAssign(lhs, rhs) => NoRawRefs(lhs) && NoRawRefs(rhs)
    case ENew(inits, newBody) => NoRawRefs(newBody)
}


lemma EVar_NoExternalEffects(x: Var)
  ensures NoExternalEffects(EVar(x))
{
  assume false;
}

lemma EConst_NoExternalEffects(v: Value)
  ensures NoExternalEffects(EConst(v))
{
  assume false;
}

predicate OnlyMethodDefinitions(e: Expr)
{
  if e.EMethod? then true
  else if e.ESeq? then OnlyMethodDefinitions(e.e1) && OnlyMethodDefinitions(e.e2)
  else false
}

lemma ENew_NoExternalEffects(locs: List<Init>, body: Expr)
  requires ListAll((loc: Init) => NoExternalEffects(loc.val), locs)
  requires OnlyMethodDefinitions(body)
  ensures NoExternalEffects(ENew(locs, body))
{
  assume false;
}

function method InsertAt<T>(x: T, n: nat, xs: List<T>): List<T>
  requires n <= Length(xs)
  decreases n
{
  if n == 0 then Cons(x, xs)
  else Cons(xs.car, InsertAt(x, n-1, xs.cdr))
}

lemma EquivalentSymmetric(lhs: Expr, rhs: Expr, ctxp: Context, Inv: ContextEquivalence)
  requires Equivalent(lhs, rhs, ctxp, Inv)
  ensures Equivalent(rhs, lhs, ctxp, Inv)
{ assume false; }

// TODO: The thing that is missing here to make this provable is probably
// to require that Inv is strong enough to imply reflexivity of lhs.
// TODO: Missing check: new name also does not occur free in local initializations
// that follow it.
lemma EquivalentAddNewField(prefix: Expr, fields: List<Init>, body: Expr, newField: Init,
  Inv: ContextEquivalence, n: nat)
  requires
    var ctxp := Eval(prefix, EmptyContext(), FUEL).1;
    var lhs := ENew(fields, body);
    var rhs := ENew(Append(fields, Cons(newField, LNil)), body);
    var (addr1, ctx1) := Eval(lhs, ctxp, FUEL);
    var (addr2, ctx2) := Eval(rhs, ctxp, FUEL);
    n <= Length(fields) &&
    AssocGet(ctx1.methods, addr1.addr) == AssocGet(ctx2.methods, addr2.addr) &&
    NoExternalEffects(newField.val) &&
    UnusedIn(newField.name, body)
  ensures
    var ctxp := Eval(prefix, EmptyContext(), FUEL).1;
    var lhs := ENew(fields, body);
    var rhs := ENew(InsertAt(newField, n, fields), body);
    Equivalent(lhs, rhs, ctxp, Inv)
{
  assume false;
}