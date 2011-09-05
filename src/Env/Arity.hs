{- |In order to generate correct FlatCurry applications it is necessary
    to define the number of arguments as the arity value (instead of
    using the arity computed from the type). For this reason the compiler
    needs a table containing the information for all known functions
    and constructors.

    September 2005, Martin Engelke (men@informatik.uni-kiel.de)
-}

module Env.Arity
  ( ArityEnv, ArityInfo (..), bindArity, lookupArity, qualLookupArity
  , qualLookupConsArity, lookupTupleArity, bindArities, initAEnv
  ) where

import Curry.Base.Ident
import Curry.Syntax

import Base.TopEnv
import Base.Types (DataConstr (..), predefTypes)
import Base.Utils ((++!))

type ArityEnv = TopEnv ArityInfo

data ArityInfo = ArityInfo QualIdent Int deriving Show

instance Entity ArityInfo where
  origName (ArityInfo orgName _) = orgName

initAEnv :: ArityEnv
initAEnv = foldr bindPredefArity emptyTopEnv $ concatMap snd predefTypes
  where bindPredefArity (DataConstr ident _ ts) =
          bindArity preludeMIdent ident (length ts)

bindArity :: ModuleIdent -> Ident -> Int -> ArityEnv -> ArityEnv
bindArity mid ident arity aEnv
  | uniqueId ident == 0 = bindTopEnv "Base.bindArity" ident arityInfo
                        $ qualBindTopEnv "Base.bindArity" qid arityInfo aEnv
  | otherwise           = bindTopEnv "Base.bindArity" ident arityInfo aEnv
 where
  qid       = qualifyWith mid ident
  arityInfo = ArityInfo qid arity

lookupArity :: Ident -> ArityEnv -> [ArityInfo]
lookupArity ident aEnv = lookupTopEnv ident aEnv ++! lookupTupleArity ident

qualLookupArity :: QualIdent -> ArityEnv -> [ArityInfo]
qualLookupArity qid aEnv = qualLookupTopEnv    qid aEnv
                       ++! qualLookupConsArity qid aEnv
                       ++! lookupTupleArity (unqualify qid)

qualLookupConsArity :: QualIdent -> ArityEnv -> [ArityInfo]
qualLookupConsArity qid aEnv
  | maybe False (== preludeMIdent) mmid && ident == consId
    = qualLookupTopEnv (qualify ident) aEnv
  | otherwise
    = []
  where (mmid, ident) = (qualidMod qid, qualidId qid)

lookupTupleArity :: Ident -> [ArityInfo]
lookupTupleArity ident
  | isTupleId ident
    = [ArityInfo (qualifyWith preludeMIdent ident) (tupleArity ident)]
  | otherwise
    = []

{- |Expand the arity envorinment with (global / local) function arities and
    constructor arities.
-}
bindArities :: ArityEnv -> Module -> ArityEnv
bindArities aEnv (Module mid _ _ decls)
  = foldl (visitDecl mid) aEnv decls

visitDecl :: ModuleIdent -> ArityEnv -> Decl -> ArityEnv
visitDecl mid aEnv (DataDecl _ _ _ cdecls)
  = foldl (visitConstrDecl mid) aEnv cdecls
visitDecl mid aEnv (ExternalDecl _ _ _ ident texpr)
  = bindArity mid ident (typeArity texpr) aEnv
visitDecl mid aEnv (FunctionDecl _ ident equs)
  = let (Equation _ lhs rhs) = head equs
    in  visitRhs mid (visitLhs mid ident aEnv lhs) rhs
visitDecl _ aEnv _ = aEnv

visitConstrDecl :: ModuleIdent -> ArityEnv -> ConstrDecl -> ArityEnv
visitConstrDecl mid aEnv (ConstrDecl _ _ ident texprs)
  = bindArity mid ident (length texprs) aEnv
visitConstrDecl mid aEnv (ConOpDecl _ _ _ ident _)
  = bindArity mid ident 2 aEnv

visitLhs :: ModuleIdent -> Ident -> ArityEnv -> Lhs -> ArityEnv
visitLhs mid _ aEnv (FunLhs ident params)
  = bindArity mid ident (length params) aEnv
visitLhs mid ident aEnv (OpLhs _ _ _)
  = bindArity mid ident 2 aEnv
visitLhs _ _ aEnv _ = aEnv

visitRhs :: ModuleIdent -> ArityEnv -> Rhs -> ArityEnv
visitRhs mid aEnv (SimpleRhs _ expr decls)
  = foldl (visitDecl mid) (visitExpr mid aEnv expr) decls
visitRhs mid aEnv (GuardedRhs cexprs decls)
  = foldl (visitDecl mid) (foldl (visitCondExpr mid) aEnv cexprs) decls

visitCondExpr :: ModuleIdent -> ArityEnv -> CondExpr -> ArityEnv
visitCondExpr mid aEnv (CondExpr _ cond expr)
  = visitExpr mid (visitExpr mid aEnv expr) cond

visitExpr :: ModuleIdent -> ArityEnv -> Expression -> ArityEnv
visitExpr mid aEnv (Paren expr)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (Typed expr _)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (Tuple _ exprs)
  = foldl (visitExpr mid) aEnv exprs
visitExpr mid aEnv (List _ exprs)
  = foldl (visitExpr mid) aEnv exprs
visitExpr mid aEnv (ListCompr _ expr stmts)
  = foldl (visitStatement mid) (visitExpr mid aEnv expr) stmts
visitExpr mid aEnv (EnumFrom expr)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (EnumFromThen expr1 expr2)
  = foldl (visitExpr mid) aEnv [expr1, expr2]
visitExpr mid aEnv (EnumFromTo expr1 expr2)
  = foldl (visitExpr mid) aEnv [expr1, expr2]
visitExpr mid aEnv (EnumFromThenTo expr1 expr2 expr3)
  = foldl (visitExpr mid) aEnv [expr1, expr2, expr3]
visitExpr mid aEnv (UnaryMinus _ expr)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (Apply expr1 expr2)
  = foldl (visitExpr mid) aEnv [expr1, expr2]
visitExpr mid aEnv (InfixApply expr1 _ expr2)
  = foldl (visitExpr mid) aEnv [expr1, expr2]
visitExpr mid aEnv (LeftSection expr _)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (RightSection _ expr)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (Lambda _ _ expr)
  = visitExpr mid aEnv expr
visitExpr mid aEnv (Let decls expr)
  = foldl (visitDecl mid) (visitExpr mid aEnv expr) decls
visitExpr mid aEnv (Do stmts expr)
  = foldl (visitStatement mid) (visitExpr mid aEnv expr) stmts
visitExpr mid aEnv (IfThenElse _ expr1 expr2 expr3)
  = foldl (visitExpr mid) aEnv [expr1, expr2, expr3]
visitExpr mid aEnv (Case _ expr alts)
  = visitExpr mid (foldl (visitAlt mid) aEnv alts) expr
visitExpr _ aEnv _ = aEnv

visitStatement :: ModuleIdent -> ArityEnv -> Statement -> ArityEnv
visitStatement mid aEnv (StmtExpr _ expr)
  = visitExpr mid aEnv expr
visitStatement mid aEnv (StmtDecl decls)
  = foldl (visitDecl mid) aEnv decls
visitStatement mid aEnv (StmtBind _ _ expr)
  = visitExpr mid aEnv expr

visitAlt :: ModuleIdent -> ArityEnv -> Alt -> ArityEnv
visitAlt mid aEnv (Alt _ _ rhs) = visitRhs mid aEnv rhs

-- |Compute the function arity of a type expression
typeArity :: TypeExpr -> Int
typeArity (ArrowType _ t2) = 1 + typeArity t2
typeArity _                = 0
