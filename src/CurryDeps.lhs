% $Id: CurryDeps.lhs,v 1.14 2004/02/09 17:10:05 wlux Exp $
%
% Copyright (c) 2002-2004, Wolfgang Lux
% See LICENSE for the full license.
%
% Modified by Martin Engelke    (men@informatik.uni-kiel.de)
% Extended by Sebastian Fischer (sebf@informatik.uni-kiel.de)
% Modified by Bjoern Peemoeller (bjp@informatik.uni-kiel.de)
%
\nwfilename{CurryDeps.lhs}
\section{Building Programs}
This module implements the functions to compute the dependency
information between Curry modules. This is used to create Makefile
dependencies and to update programs composed of multiple modules.
\begin{verbatim}

> module CurryDeps
>   ( Source (..), deps, flatDeps, flattenDeps, sourceDeps, moduleDeps ) where

> import Control.Monad (foldM)
> import Data.List (intercalate, isSuffixOf, nub)
> import qualified Data.Map as Map (Map, empty, insert, lookup, toList)

> import Curry.Base.Ident
> import Curry.Base.MessageMonad
> import Curry.Files.Filenames
> import Curry.Files.PathUtils
> import Curry.Syntax hiding (Interface (..))

> import Base.SCC (scc)
> import CompilerOpts (Options (..), Extension (..))

> data Source
>   = Source FilePath [ModuleIdent]
>   | Interface FilePath
>   | Unknown
>     deriving (Eq, Ord, Show)

> type SourceEnv = Map.Map ModuleIdent Source

> flatDeps :: Options -> FilePath -> IO ([(ModuleIdent, Source)], [String])
> flatDeps opts fn = do
>   mEnv <- deps implicitPrelude [] libPaths Map.empty fn
>   return $ flattenDeps mEnv
>   where
>     implicitPrelude = NoImplicitPrelude `notElem` optExtensions opts
>     libPaths = optImportPaths opts

> deps :: Bool -> [FilePath] -> [FilePath] -> SourceEnv -> FilePath
>      -> IO SourceEnv
> deps implicitPrelude paths libPaths mEnv fn
>   | e `elem` sourceExts
>     = sourceDeps implicitPrelude paths libPaths (mkMIdent [r]) mEnv fn
>   | e == icurryExt
>     = return Map.empty
>   | e `elem` objectExts
>     = targetDeps implicitPrelude paths libPaths mEnv r
>   | otherwise
>     = targetDeps implicitPrelude paths libPaths mEnv fn
>   where r = dropExtension fn
>         e = takeExtension fn

> targetDeps :: Bool -> [FilePath] -> [FilePath] -> SourceEnv -> FilePath
>            -> IO SourceEnv
> targetDeps implicitPrelude paths libraryPaths mEnv fn =
>   lookupFile [""] sourceExts fn >>=
>   maybe (return (Map.insert m Unknown mEnv))
>         (sourceDeps implicitPrelude paths libraryPaths m mEnv)
>   where m = mkMIdent [fn]

\end{verbatim}
The following functions are used to lookup files related to a given
module. Source files for targets are looked up in the current
directory only. Two different search paths are used to look up
imported modules, the first is used to find source modules, whereas
the library path is used only for finding matching interface files. As
the compiler does not distinguish these paths, we actually check for
interface files in the source paths as well.

Note that the functions \texttt{buildScript} and \texttt{makeDepend}
already remove all directories that are included in the both search
paths from the library paths in order to avoid scanning such
directories more than twice.
\begin{verbatim}

\end{verbatim}
In order to compute the dependency graph, source files for each module
need to be looked up. When a source module is found, its header is
parsed in order to determine the modules that it imports, and
dependencies for these modules are computed recursively. The prelude
is added implicitly to the list of imported modules except for the
prelude itself. Any errors reported by the parser are ignored.
\begin{verbatim}

> moduleDeps :: Bool -> [FilePath] -> [FilePath] -> SourceEnv -> ModuleIdent
>            -> IO SourceEnv
> moduleDeps implicitPrelude paths libraryPaths mEnv m =
>   case Map.lookup m mEnv of
>     Just _  -> return mEnv
>     Nothing -> do
>       mbFn <- lookupModule paths libraryPaths m
>       case mbFn of
>         Just fn
>           | icurryExt `isSuffixOf` fn ->
>               return (Map.insert m (Interface fn) mEnv)
>           | otherwise -> sourceDeps implicitPrelude paths libraryPaths m mEnv fn
>         Nothing -> return (Map.insert m Unknown mEnv)

> sourceDeps :: Bool -> [FilePath] -> [FilePath] -> ModuleIdent -> SourceEnv
>            -> FilePath -> IO SourceEnv
> sourceDeps implicitPrelude paths libraryPaths m mEnv fn = do
>   s <- readModule fn
>   case fst $ runMsg $ parseHeader fn s of
>     Right (Module m' _ ds) ->
>       let ms = imports implicitPrelude m' ds in
>       foldM (moduleDeps implicitPrelude paths libraryPaths)
>             (Map.insert m (Source fn ms) mEnv) ms
>     Left _ -> return (Map.insert m (Source fn []) mEnv)

> -- |Retrieve the imported modules and add the import of the Prelude
> --  according to the flag.
> imports :: Bool -> ModuleIdent -> [Decl] -> [ModuleIdent]
> imports implicitPrelude m ds = nub $
>      [preludeMIdent | m /= preludeMIdent && implicitPrelude]
>   ++ [m' | ImportDecl _ m' _ _ _ <- ds]

If we want to compile the program instead of generating Makefile
dependencies the environment has to be sorted topologically. Note
that the dependency graph should not contain any cycles.

> flattenDeps :: SourceEnv -> ([(ModuleIdent, Source)], [String])
> flattenDeps = fdeps . sortDeps where
>   sortDeps :: SourceEnv -> [[(ModuleIdent, Source)]]
>   sortDeps = scc modules imports' . Map.toList
>
>   modules (m, _) = [m]
>
>   imports' (_, Source _ ms) = ms
>   imports' (_, Interface _) = []
>   imports' (_, Unknown    ) = []
>
>   fdeps :: [[(ModuleIdent, Source)]] -> ([(ModuleIdent, Source)], [String])
>   fdeps = foldr checkdep ([], [])
>
>   checkdep []    (srcs, errs) = (srcs      , errs      )
>   checkdep [src] (srcs, errs) = (src : srcs, errs      )
>   checkdep dep   (srcs, errs) = (srcs      , err : errs)
>     where err = cyclicError (map fst dep)

>   cyclicError :: [ModuleIdent] -> String
>   cyclicError ms = "Cylic import dependency between modules " ++
>                    intercalate ", " inits ++ " and " ++ lastm where
>     (inits, lastm)         = splitLast $ map moduleName ms
>     splitLast []           = error "CurryDeps.splitLast: empty list"
>     splitLast (x : [])     = ([]  , x)
>     splitLast (x : y : ys) = (x : xs, z)
>        where (xs, z) = splitLast (y : ys)
