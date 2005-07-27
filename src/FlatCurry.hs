------------------------------------------------------------------------------
--- Library to support meta-programming in Curry.
---
--- This library contains a definition for representing FlatCurry programs
--- in Haskell (type "Prog").
---
--- @author Michael Hanus
--- @version September 2003
---
--- Version for Haskell (slightly modified):
---  December 2004, Martin Engelke (men@informatik.uni-kiel.de)
---
------------------------------------------------------------------------------

module FlatCurry (Prog(..), QName, Visibility(..),
                  TVarIndex, TypeDecl(..), ConsDecl(..), TypeExpr(..),
                  OpDecl(..), Fixity(..),
                  VarIndex, 
                  FuncDecl(..), Rule(..), 
                  CaseType(..), CombType(..), Expr(..), BranchExpr(..),
                  Pattern(..), Literal(..),
		  readFlatCurry, writeFlatCurry) where


------------------------------------------------------------------------------
-- Definition of data types for representing FlatCurry programs:
-- =============================================================

--- Data type for representing a Curry module in the intermediate form.
--- A value of this data type has the form
--- <CODE>
---  (Prog modname imports typedecls functions opdecls translation_table)
--- </CODE>
--- where modname: name of this module,
---       imports: list of modules names that are imported,
---       typedecls, opdecls, functions, translation of type names
---       and constructor/function names: see below

data Prog = Prog String [String] [TypeDecl] [FuncDecl] [OpDecl] 
	    deriving (Read, Show)


--- The data type for representing qualified names.
--- In FlatCurry all names are qualified to avoid name clashes.
--- The first component is the module name and the second component the
--- unqualified name as it occurs in the source program.

type QName = (String,String)

--- Data type to specify the visibility of various entities.

data Visibility = Public    -- public (exported) entity
                | Private   -- private entity
		deriving (Read, Show, Eq)

--- The data type for representing type variables.
--- They are represented by (TVar i) where i is a type variable index.

type TVarIndex = Int

--- Data type for representing definitions of algebraic data types.
--- <PRE>
--- A data type definition of the form
---
--- data t x1...xn = ...| c t1....tkc |...
---
--- is represented by the FlatCurry term
---
--- (Type t [i1,...,in] [...(Cons c kc [t1,...,tkc])...])
---
--- where each ij is the index of the type variable xj
---
--- Note: the type variable indices are unique inside each type declaration
---       and are usually numbered from 0
---
--- Thus, a data type declaration consists of the name of the data type,
--- a list of type parameters and a list of constructor declarations.
--- </PRE>

data TypeDecl = Type    QName Visibility [TVarIndex] [ConsDecl]
              | TypeSyn QName Visibility [TVarIndex] TypeExpr
	      deriving (Read, Show)

--- A constructor declaration consists of the name and arity of the
--- constructor and a list of the argument types of the constructor.

data ConsDecl = Cons QName Int Visibility [TypeExpr]
	      deriving (Read, Show)


--- Data type for type expressions.
--- A type expression is either a type variable, a function type,
--- or a type constructor application.
---
--- Note: the names of the predefined type constructors are
---       "Int", "Float", "Bool", "Char", "IO", "Success",
---       "()" (unit type), "(,...,)" (tuple types), "[]" (list type)

data TypeExpr =
     TVar TVarIndex                 -- type variable
   | FuncType TypeExpr TypeExpr     -- function type t1->t2
   | TCons QName [TypeExpr]         -- type constructor application
   deriving (Read, Show)            --    TCons module name typeargs


--- Data type for operator declarations.
--- An operator declaration "fix p n" in Curry corresponds to the
--- FlatCurry term (Op n fix p).
--- Note: the constructor definition of 'Op' differs from the original
--- PAKCS definition using Haskell type 'Integer' instead of 'Int'
--- for representing the precedence.

data OpDecl = Op QName Fixity Integer deriving (Read, Show)

--- Data types for the different choices for the fixity of an operator.

data Fixity = InfixOp | InfixlOp | InfixrOp deriving (Read, Show)


--- Data type for representing object variables.
--- Object variables occurring in expressions are represented by (Var i)
--- where i is a variable index.

type VarIndex = Int


--- Data type for representing function declarations.
--- <PRE>
--- A function declaration in FlatCurry is a term of the form
---
---  (Func name arity type (Rule [i_1,...,i_arity] e))
---
--- and represents the function "name" with definition
---
---   name :: type
---   name x_1...x_arity = e
---
--- where each i_j is the index of the variable x_j
---
--- Note: the variable indices are unique inside each function declaration
---       and are usually numbered from 0
---
--- External functions are represented as (Func name arity type (External s))
--- where s is the external name associated to this function.
---
--- Thus, a function declaration consists of the name, arity, type, and rule.
--- </PRE>

data FuncDecl = Func QName Int Visibility TypeExpr Rule
	      deriving (Read, Show)


--- A rule is either a list of formal parameters together with an expression
--- or an "External" tag.

data Rule = Rule [VarIndex] Expr
          | External String
	  deriving (Read, Show)

--- Data type for classifying case expressions.
--- Case expressions can be either flexible or rigid in Curry.

data CaseType = Rigid | Flex deriving (Read, Show)

--- Data type for classifying combinations
--- (i.e., a function/constructor applied to some arguments).
--- @cons FuncCall - a call to a function where all arguments are provided
--- @cons PartCall - a partial call to a function (i.e., not all arguments
---                  are provided) where the parameter is the number of
---                  missing arguments
--- @cons ConsCall - a call with a constructor at the top (where it is
---                  possible that not all arguments are provided)

data CombType = FuncCall | PartCall Int | ConsCall deriving (Read, Show)

--- Data type for representing expressions.
---
--- Remarks:
--- <PRE>
--- 1. if-then-else expressions are represented as function calls:
---      (if e1 then e2 else e3)
---    is represented as
---      (Comb FuncCall ("prelude","if_then_else") [e1,e2,e3])
--- 
--- 2. Higher order applications are represented as calls to the (external)
---    function "apply". For instance, the rule
---      app f x = f x
---    is represented as
---      (Rule  [0,1] (Comb FuncCall ("prelude","apply") [Var 0, Var 1]))
--- 
--- 3. A conditional rule is represented as a call to an external function
---    "cond" where the first argument is the condition (a constraint).
---    For instance, the rule
---      equal2 x | x=:=2 = success
---    is represented as
---      (Rule [0]
---            (Comb FuncCall ("prelude","cond")
---                  [Comb FuncCall ("prelude","=:=") [Var 0, Lit (Intc 2)],
---                   Comb FuncCall ("prelude","success") []]))
--- 
--- 4. Functions with evaluation annotation "choice" are represented
---    by a rule whose right-hand side is enclosed in a call to the
---    external function "prelude.commit".
---    Furthermore, all rules of the original definition must be
---    represented by conditional expressions (i.e., (cond [c,e]))
---    after pattern matching.
---    Example:
--- 
---       m eval choice
---       m [] y = y
---       m x [] = x
--- 
---    is translated into (note that the conditional branches can be also
---    wrapped with Free declarations in general):
--- 
---       Rule [0,1]
---            (Comb FuncCall ("prelude","commit")
---              [Or (Case Rigid (Var 0)
---                     [(Pattern ("prelude","[]") []
---                         (Comb FuncCall ("prelude","cond")
---                               [Comb FuncCall ("prelude","success") [],
---                                Var 1]))] )
---                  (Case Rigid (Var 1)
---                     [(Pattern ("prelude","[]") []
---                         (Comb FuncCall ("prelude","cond")
---                               [Comb FuncCall ("prelude","success") [],
---                                Var 0]))] )])
--- 
---    Operational meaning of (prelude.commit e):
---    evaluate e with local search spaces and commit to the first
---    (Comb FuncCall ("prelude","cond") [c,ge]) in e whose constraint c
---    is satisfied
--- </PRE>
--- @cons Var - variable (represented by unique index)
--- @cons Lit - literal (Integer/Float/Char constant)
--- @cons Comb - application (f e1 ... en) of function/constructor f
---              with n<=arity(f)
--- @cons Free - introduction of free local variables
--- @cons Or - disjunction of two expressions (used to translate rules
---            with overlapping left-hand sides)
--- @cons Case - case distinction (rigid or flex)

data Expr = Var VarIndex 
          | Lit Literal
          | Comb CombType QName [Expr]
          | Free [VarIndex] Expr
          | Let [(VarIndex,Expr)] Expr
          | Or Expr Expr
          | Case CaseType Expr [BranchExpr]
	  deriving (Read, Show)


--- Data type for representing branches in a case expression.
--- <PRE>
--- Branches "(m.c x1...xn) -> e" in case expressions are represented as
---
---   (Branch (Pattern (m,c) [i1,...,in]) e)
---
--- where each ij is the index of the pattern variable xj, or as
---
---   (Branch (LPattern (Intc i)) e)
---
--- for integers as branch patterns (similarly for other literals
--- like float or character constants).
--- </PRE>

data BranchExpr = Branch Pattern Expr deriving (Read, Show)

--- Data type for representing patterns in case expressions.

data Pattern = Pattern QName [VarIndex]
             | LPattern Literal
	     deriving (Read, Show)

--- Data type for representing literals occurring in an expression
--- or case branch. It is either an integer, a float, or a character constant.
--- Note: the constructor definition of 'Intc' differs from the original
--- PAKCS definition. It uses Haskell type 'Integer' instead of 'Int'
--- to provide an unlimited range of integer numbers. Furthermore
--- float values are represented with Haskell type 'Double' instead of
--- 'Float'.

data Literal = Intc   Integer
             | Floatc Double
             | Charc  Char
	     deriving (Read, Show)


------------------------------------------------------------------------------
------------------------------------------------------------------------------

-- Reads a FlatCurry file and returns the corresponding FlatCurry
-- program term (type 'Prog')
readFlatCurry :: String -> IO Prog
readFlatCurry filename
   = do file <- readFile filename
	let prog = (read file) :: Prog
        return prog


-- Writes a FlatCurry program term into a file
writeFlatCurry :: String -> Prog -> IO ()
writeFlatCurry filename prog
   = writeFile filename (show prog)


------------------------------------------------------------------------------
------------------------------------------------------------------------------

