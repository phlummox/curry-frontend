{- |
    Module      :  $Header$
    Description :  Provides internal names used in transformations 
    Copyright   :  2013 Matthias Böhm
    License     :  OtherLicense

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable
    
    This module exports name generation functions, e.g. for dictionary selector
    functions and for internal function names in connection with instances
-}

module Base.Names 
  (sep, implPrefix, dictTypePrefix
    -- * name generation functions
  , mkSelFunName, mkDictName
  ) where

-- |The prefix for dictionary types
dictTypePrefix :: String
dictTypePrefix = "Dict" ++ sep

-- |The prefix for dictionaries
dictPrefix :: String
dictPrefix = "dict" ++ sep

-- |The prefix for selector functions
selFunPrefix :: String
selFunPrefix = "sel" ++ sep

-- |The prefix for functions that are implemented in a given instance declaration
implPrefix :: String
implPrefix = "impl" ++ sep

-- |creates a name for a selection function 
mkSelFunName :: String -> String -> String
mkSelFunName cls what = 
  selFunPrefix ++ cls ++ sep ++ what
  
-- |create a name for a dictionary
mkDictName :: String -> String -> String
mkDictName cls ty = dictPrefix ++ cls ++ sep ++ ty

-- |internal separator
sep :: String
sep = "."
