include "../../src/backend/dafny/Lang.dfy"
include "../../src/backend/dafny/Indistinguishable.dfy"
include "../../src/backend/dafny/Refl.dfy"
include "../../src/backend/dafny/Rules.dfy"
const True := true; const False := false;

method Main()
{
  var unevaled := ENew(Cons(Init("e", EVar("_e"), true), Cons(Init("mac", ECall(EConst(Nil()), "MacI", Cons(EVar("_mac"), LNil)), true), LNil)), ESeq(EMethod("enc", Cons("a", Cons("m", LNil)), ECall(EConst(Nil()), "&", Cons(ECall(EConst(Nil()), "&", Cons(ECall(EConst(Nil()), "&", Cons(EVar("m"), Cons(EAssign(EVar("em"), ECall(EVar("e"), "enc", Cons(EVar("m"), LNil))), LNil))), Cons(EAssign(EVar("t"), ECall(EVar("mac"), "tag", Cons(ETuple(Cons(EVar("a"), Cons(EVar("em"), LNil))), LNil))), LNil))), Cons(ETuple(Cons(EVar("em"), Cons(EVar("t"), LNil))), LNil)))), EMethod("dec", Cons("a", Cons("c", LNil)), ESeq(EAssign(EVar("em"), ECVar(EVar("c"), "get", EConst(Int(0)))), ESeq(EAssign(EVar("t"), ECVar(EVar("c"), "get", EConst(Int(1)))), ECall(EConst(Nil()), "&", Cons(ECall(EConst(Nil()), "&", Cons(EVar("c"), Cons(ECall(EVar("mac"), "verify", Cons(ETuple(Cons(EVar("a"), Cons(EVar("em"), LNil))), Cons(EVar("t"), LNil))), LNil))), Cons(ECall(EVar("e"), "dec", Cons(EVar("em"), LNil)), LNil))))))));
  var rhs := ENew(Cons(Init("e", EVar("_e"), true), Cons(Init("mac", ECall(EConst(Nil()), "MacI", Cons(EVar("_mac"), LNil)), true), Cons(Init("cpa", ENew(Cons(Init("e", EVar("_e"), true), LNil), ESeq(EMethod("enc", Cons("m", LNil), ECall(EVar("e"), "enc", Cons(EVar("m"), LNil))), EMethod("dec", Cons("c", LNil), ECall(EVar("e"), "dec", Cons(EVar("c"), LNil))))), true), LNil))), ESeq(EMethod("enc", Cons("a", Cons("m", LNil)), ECall(EConst(Nil()), "&", Cons(ECall(EConst(Nil()), "&", Cons(ECall(EConst(Nil()), "&", Cons(EVar("m"), Cons(EAssign(EVar("em"), ECall(EVar("e"), "enc", Cons(EVar("m"), LNil))), LNil))), Cons(EAssign(EVar("t"), ECall(EVar("mac"), "tag", Cons(ETuple(Cons(EVar("a"), Cons(EVar("em"), LNil))), LNil))), LNil))), Cons(ETuple(Cons(EVar("em"), Cons(EVar("t"), LNil))), LNil)))), EMethod("dec", Cons("a", Cons("c", LNil)), ESeq(EAssign(EVar("em"), ECVar(EVar("c"), "get", EConst(Int(0)))), ESeq(EAssign(EVar("t"), ECVar(EVar("c"), "get", EConst(Int(1)))), ECall(EConst(Nil()), "&", Cons(ECall(EConst(Nil()), "&", Cons(EVar("c"), Cons(ECall(EVar("mac"), "verify", Cons(ETuple(Cons(EVar("a"), Cons(EVar("em"), LNil))), Cons(EVar("t"), LNil))), LNil))), Cons(ECall(EVar("e"), "dec", Cons(EVar("em"), LNil)), LNil))))))));
  var newField := Init("cpa", ENew(Cons(Init("e", EVar("_e"), true), LNil), ESeq(EMethod("enc", Cons("m", LNil), ECall(EVar("e"), "enc", Cons(EVar("m"), LNil))), EMethod("dec", Cons("c", LNil), ECall(EVar("e"), "dec", Cons(EVar("c"), LNil))))), true);
  print UnusedIn("cpa", unevaled.body), "\n";
  print InsertAt(newField, 2, unevaled.locals) == rhs.locals, "\n";
}