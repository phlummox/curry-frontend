module ScopeEnv (ScopeEnv,
		 newScopeEnv,
		 insertIdent, getIdentLevel,
		 isVisible, isDeclared,
		 beginScope, endScope,
		 getLevel,
		 genIdent, genIdentList) where

import Ident
import Env
import Maybe


-------------------------------------------------------------------------------

-- Type for representing an environment containing identifiers in several
-- scope levels
type ScopeEnv = (IdEnv, [IdEnv], Int)

-------------------------------------------------------------------------------

-- Generates a new instance of a scope table
newScopeEnv :: ScopeEnv
newScopeEnv = (newIdEnv, [], 0)


-- Inserts an identifier into the current level of the scope environment
insertIdent :: Ident -> ScopeEnv -> ScopeEnv
insertIdent ident (topleveltab, leveltabs, level)
   = case leveltabs of
       (lt:lts) -> (topleveltab, (insertId level ident lt):lts, level)
       []       -> ((insertId level ident topleveltab), [], 0)


-- Returns the declaration level of an identifier if it exists
getIdentLevel :: Ident -> ScopeEnv -> Maybe Int
getIdentLevel ident (topleveltab, leveltabs, _)
   = case leveltabs of
       (lt:_) -> maybe (getIdLevel ident topleveltab) Just (getIdLevel ident lt)
       []     -> getIdLevel ident topleveltab


-- Checks whether the specified identifier is visible in the current scope
-- (i.e. checks whether the identifier occurs in the scope environment)
isVisible :: Ident -> ScopeEnv -> Bool
isVisible ident (topleveltab, leveltabs, _)
   = case leveltabs of
       (lt:_) -> idExists ident lt || idExists ident topleveltab
       []     -> idExists ident topleveltab


-- Checks whether the specified identifier is declared in the
-- current scope (i.e. checks whether the identifier occurs in the
-- current level of the scope environment)
isDeclared :: Ident -> ScopeEnv -> Bool
isDeclared ident (topleveltab, leveltabs, level)
   = case leveltabs of
       (lt:_) -> maybe False ((==) level) (getIdLevel ident lt)
       []     -> maybe False ((==) 0) (getIdLevel ident topleveltab)


-- Increases the level of the scope.
beginScope :: ScopeEnv -> ScopeEnv
beginScope (topleveltab, leveltabs, level)
   = case leveltabs of
       (lt:lts) -> (topleveltab, (lt:lt:lts), level + 1)
       []       -> (topleveltab, [newIdEnv], 1)


-- Decreases the level of the scope. Identifier from higher levels
-- will be lost.
endScope :: ScopeEnv -> ScopeEnv
endScope (topleveltab, leveltabs, level)
   = case leveltabs of
       (_:lts) -> (topleveltab, lts, level - 1)
       []      -> (topleveltab, [], 0)


-- Returns the level of the current scope. Top level is 0
getLevel :: ScopeEnv -> Int
getLevel (_, _, level) = level


-- Generates a new identifier for the specified name. The new identifier is 
-- unique within the current scope. If no identifier can be generated for 
-- 'name' then 'Nothing' will be returned
genIdent :: String -> ScopeEnv -> Maybe Ident
genIdent name (topleveltab, leveltabs, _)
   = case leveltabs of
       (lt:_) -> genId name lt
       []     -> genId name topleveltab


-- Generates a list of new identifiers where each identifier consits of
-- a prefix 'name' and an index (i.e. "var3" if 'name' is "var").
-- All returned identifiers are unique within the current scope.
genIdentList :: Int -> String -> ScopeEnv -> [Ident]
genIdentList size name scopeenv = p_genIdentList size name scopeenv 0
 where
   p_genIdentList s n env i
      | s == 0 
	= []
      | otherwise
	= maybe (p_genIdentList s n env (i + 1))
	        (\ident -> ident:(p_genIdentList (s - 1) 
				                 n 
				                 (insertIdent ident env) 
				                 (i + 1)))
		(genIdent (n ++ (show i)) env)



-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Private declarations...

type IdEnv = Env IdRep Int

data IdRep = Name String | Index Int deriving (Eq, Ord)


-------------------------------------------------------------------------------

--
newIdEnv :: IdEnv
newIdEnv = emptyEnv


--
insertId :: Int -> Ident -> IdEnv -> IdEnv
insertId level ident env
   = bindEnv (Name (name ident)) 
             level 
	     (bindEnv (Index (uniqueId ident)) level env)


--
idExists :: Ident -> IdEnv -> Bool
idExists ident env = indexExists (uniqueId ident) env


--
getIdLevel :: Ident -> IdEnv -> Maybe Int
getIdLevel ident env = lookupEnv (Index (uniqueId ident)) env


--
genId n env
   | nameExists n env = Nothing
   | otherwise        = Just (p_genId (mkIdent n) 0)
 where
   p_genId ident index
      | indexExists index env = p_genId ident (index + 1)
      | otherwise             = renameIdent ident index


--
nameExists :: String -> IdEnv -> Bool
nameExists name env = isJust (lookupEnv (Name name) env)


--
indexExists :: Int -> IdEnv -> Bool
indexExists index env = isJust (lookupEnv (Index index) env)


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
