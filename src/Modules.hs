{- |
    Module      :  $Header$
    Description :  Compilation of a single module
    Copyright   :  (c) 1999 - 2004 Wolfgang Lux
                       2005        Martin Engelke
                       2007        Sebastian Fischer
                       2011 - 2015 Björn Peemöller
                       2016        Jan Tikovsky
    License     :  BSD-3-clause

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

    This module controls the compilation of modules.
-}

module Modules
  ( compileModule, loadAndCheckModule, loadModule, checkModule
  , parseModule, checkModuleHeader
  ) where

import qualified Control.Exception as C   (catch, IOException)
import           Control.Monad            (liftM, unless, when)
import           Data.Char                (toUpper)
import qualified Data.Map          as Map (elems, lookup)
import           Data.Maybe               (fromMaybe)
import           System.Directory         (getTemporaryDirectory, removeFile)
import           System.Exit              (ExitCode (..))
import           System.FilePath          (normalise)
import           System.IO
   (IOMode (ReadMode), Handle, hClose, hGetContents, hPutStr, openFile
  , openTempFile)
import           System.Process           (system)

import Curry.Base.Ident
import Curry.Base.Monad
import Curry.Base.Position
import Curry.Base.Pretty
import Curry.Base.Span
import Curry.ExtendedFlat.InterfaceEquivalence (eqInterface)
import Curry.Files.Filenames
import Curry.Files.PathUtils
import Curry.Syntax.InterfaceEquivalence

import Base.Messages
import Env.Interface

-- source representations
import qualified Curry.AbstractCurry as AC
import qualified Curry.ExtendedFlat  as EF
import qualified Curry.Syntax        as CS
import qualified IL                  as IL

import Checks
import CompilerEnv
import CompilerOpts
import Exports
import Generators
import Html.CurryHtml (source2html)
import Imports
import Interfaces (loadInterfaces)
import TokenStream (showTokenStream)
import Transformations

-- The function 'compileModule' is the main entry-point of this
-- module for compiling a Curry source module. Depending on the command
-- line options, it will emit either FlatCurry code or AbstractCurry code
-- (typed, untyped or with type signatures) for the module.
-- Usually, the first step is to check the module.
-- Then the code is translated into the intermediate
-- language. If necessary, this phase will also update the module's
-- interface file. The resulting code then is written out
-- to the corresponding file.
-- The untyped  AbstractCurry representation is written
-- out directly after parsing and simple checking the source file.
-- The typed AbstractCurry code is written out after checking the module.
--
-- The compiler automatically loads the prelude when compiling any
-- module, except for the prelude itself, by adding an appropriate import
-- declaration to the module.
compileModule :: Options -> ModuleIdent -> FilePath -> CYIO ()
compileModule opts m fn = do
  mdl <- loadAndCheckModule opts m fn
  writeTokens opts (fst mdl)
  writeParsed opts mdl
  writeHtml   opts (qual mdl)
  mdl' <- expandExports opts mdl
  qmdl <- dumpWith opts CS.showModule CS.ppModule DumpQualified $ qual mdl'
  writeAbstractCurry opts qmdl
  -- generate interface file
  let intf = uncurry exportInterface qmdl
  writeInterface opts (fst mdl') intf
  when withFlat $ do
    (env2, il) <- transModule opts qmdl
    writeFlat opts env2 intf (snd qmdl) il
  where
  withFlat = any (`elem` optTargetTypes opts) [FlatCurry, ExtendedFlatCurry]

loadAndCheckModule :: Options -> ModuleIdent -> FilePath
                   -> CYIO (CompEnv CS.Module)
loadAndCheckModule opts m fn = do
  ce <- loadModule opts m fn >>= checkModule opts
  warnMessages $ uncurry (warnCheck opts) ce
  return ce

-- ---------------------------------------------------------------------------
-- Loading a module
-- ---------------------------------------------------------------------------

loadModule :: Options -> ModuleIdent -> FilePath -> CYIO (CompEnv CS.Module)
loadModule opts m fn = do
  -- parse and check module header
  (toks, mdl) <- parseModule opts m fn
  -- load the imported interfaces into an InterfaceEnv
  let paths = map (addCurrySubdir (optUseSubdir opts))
                  ("." : optImportPaths opts)
  iEnv   <- loadInterfaces paths mdl
  checkInterfaces opts iEnv
  is     <- importSyntaxCheck iEnv mdl
  -- add information of imported modules
  cEnv   <- importModules mdl iEnv is
  return (cEnv { filePath = fn, tokens = toks }, mdl)

parseModule :: Options -> ModuleIdent -> FilePath
            -> CYIO ([(Span, CS.Token)], CS.Module)
parseModule opts m fn = do
  mbSrc <- liftIO $ readModule fn
  case mbSrc of
    Nothing  -> failMessages [message $ text $ "Missing file: " ++ fn]
    Just src -> do
      ul      <- liftCYM $ CS.unlit fn src
      prepd   <- preprocess (optPrepOpts opts) fn ul
      -- We ignore the warnings issued by the lexer because
      -- they will be issued a second time during parsing.
      spanToks <- liftCYM $ silent $ CS.lexSource fn prepd
      ast      <- liftCYM $ CS.parseModule fn prepd
      checked  <- checkModuleHeader opts m fn ast
      return (spanToks, checked)

preprocess :: PrepOpts -> FilePath -> String -> CYIO String
preprocess opts fn src
  | not (ppPreprocess opts) = return src
  | otherwise               = do
    res <- liftIO $ withTempFile $ \ inFn inHdl -> do
      hPutStr inHdl src
      hClose inHdl
      withTempFile $ \ outFn outHdl -> do
        hClose outHdl
        ec <- system $ unwords $
          [ppCmd opts, normalise fn, inFn, outFn] ++ ppOpts opts
        case ec of
          ExitFailure x -> return $ Left [message $ text $
              "Preprocessor exited with exit code " ++ show x]
          ExitSuccess   -> Right `liftM` readFile outFn
    either failMessages ok res

withTempFile :: (FilePath -> Handle -> IO a) -> IO a
withTempFile act = do
  tmp       <- getTemporaryDirectory
  (fn, hdl) <- openTempFile tmp "cymake.curry"
  res       <- act fn hdl
  hClose hdl
  removeFile fn
  return res

checkModuleHeader :: Monad m => Options -> ModuleIdent -> FilePath -> CS.Module
                  -> CYT m CS.Module
checkModuleHeader opts m fn = checkModuleId m
                            . importPrelude opts
                            . CS.patchModuleId fn

-- |Check whether the 'ModuleIdent' and the 'FilePath' fit together
checkModuleId :: Monad m => ModuleIdent -> CS.Module -> CYT m CS.Module
checkModuleId mid m@(CS.Module _ mid' _ _ _)
  | mid == mid' = ok m
  | otherwise   = failMessages [errModuleFileMismatch mid']

-- An implicit import of the prelude is added to the declarations of
-- every module, except for the prelude itself, or when the import is disabled
-- by a compiler option. If no explicit import for the prelude is present,
-- the prelude is imported unqualified, otherwise a qualified import is added.
importPrelude :: Options -> CS.Module -> CS.Module
importPrelude opts m@(CS.Module ps mid es is ds)
    -- the Prelude itself
  | mid == preludeMIdent          = m
    -- disabled by compiler option
  | noImpPrelude                  = m
    -- already imported
  | preludeMIdent `elem` imported = m
    -- let's add it!
  | otherwise                     = CS.Module ps mid es (preludeImp : is) ds
  where
  noImpPrelude = NoImplicitPrelude `elem` optExtensions opts
                 || m `CS.hasLanguageExtension` NoImplicitPrelude
  preludeImp   = CS.ImportDecl NoPos preludeMIdent
                  False   -- qualified?
                  Nothing -- no alias
                  Nothing -- no selection of types, functions, etc.
  imported     = [imp | (CS.ImportDecl _ imp _ _ _) <- is]

checkInterfaces :: Monad m => Options -> InterfaceEnv -> CYT m ()
checkInterfaces opts iEnv = mapM_ checkInterface (Map.elems iEnv)
  where
  checkInterface intf = do
    let env = importInterfaces intf iEnv
    interfaceCheck opts (env, intf)

importSyntaxCheck :: Monad m => InterfaceEnv -> CS.Module -> CYT m [CS.ImportDecl]
importSyntaxCheck iEnv (CS.Module _ _ _ imps _) = mapM checkImportDecl imps
  where
  checkImportDecl (CS.ImportDecl p m q asM is) = case Map.lookup m iEnv of
    Just intf -> CS.ImportDecl p m q asM `liftM` importCheck intf is
    Nothing   -> internalError $ "Modules.importModules: no interface for "
                                    ++ show m

-- ---------------------------------------------------------------------------
-- Checking a module
-- ---------------------------------------------------------------------------

-- TODO: The order of the checks should be improved!
checkModule :: Options -> CompEnv CS.Module -> CYIO (CompEnv CS.Module)
checkModule opts mdl = do
  _  <- dumpCS DumpParsed mdl
   -- Should be separated into kind checking and type syntax checking (see MCC)
  kc <- kindCheck   opts mdl >>= dumpCS DumpKindChecked
  sc <- syntaxCheck opts kc  >>= dumpCS DumpSyntaxChecked
  pc <- precCheck   opts sc  >>= dumpCS DumpPrecChecked
  tc <- typeCheck   opts pc  >>= dumpCS DumpTypeChecked
  ec <- exportCheck opts tc  >>= dumpCS DumpExportChecked
  return ec
  where dumpCS = dumpWith opts CS.showModule CS.ppModule

-- ---------------------------------------------------------------------------
-- Translating a module
-- ---------------------------------------------------------------------------

transModule :: Options -> CompEnv CS.Module -> CYIO (CompEnv IL.Module)
transModule opts mdl = do
  desugared   <- dumpCS DumpDesugared     $ desugar      mdl
  simplified  <- dumpCS DumpSimplified    $ simplify     desugared
  lifted      <- dumpCS DumpLifted        $ lift         simplified
  il          <- dumpIL DumpTranslated    $ ilTrans      lifted
  ilCaseComp  <- dumpIL DumpCaseCompleted $ completeCase il
  return ilCaseComp
  where
  dumpCS = dumpWith opts CS.showModule CS.ppModule
  dumpIL = dumpWith opts IL.showModule IL.ppModule

-- ---------------------------------------------------------------------------
-- Writing output
-- ---------------------------------------------------------------------------

-- The functions \texttt{genFlat} and \texttt{genAbstract} generate
-- flat and abstract curry representations depending on the specified option.
-- If the interface of a modified Curry module did not change, the
-- corresponding file name will be returned within the result of 'genFlat'
-- (depending on the compiler flag "force") and other modules importing this
-- module won't be dependent on it any longer.

writeTokens :: Options -> CompilerEnv -> CYIO ()
writeTokens opts env = when tokTarget $ liftIO $
  writeModule (useSubDir $ tokensName (filePath env))
              (showTokenStream (tokens env))
  where
  tokTarget  = Tokens `elem` optTargetTypes opts
  useSubDir  = addCurrySubdirModule (optUseSubdir opts) (moduleIdent env)

-- |Output the parsed 'Module' on request
writeParsed :: Options -> CompEnv CS.Module -> CYIO ()
writeParsed opts (env, mdl) = when srcTarget $ liftIO $
  writeModule (useSubDir $ sourceRepName (filePath env)) (CS.showModule mdl)
  where
  srcTarget  = Parsed `elem` optTargetTypes opts
  useSubDir  = addCurrySubdirModule (optUseSubdir opts) (moduleIdent env)

writeHtml :: Options -> CompEnv CS.Module -> CYIO ()
writeHtml opts (env, mdl) = when htmlTarget $
  source2html opts (moduleIdent env) (map (\(sp, tok) -> (span2Pos sp, tok)) (tokens env)) mdl
  where htmlTarget = Html `elem` optTargetTypes opts

writeInterface :: Options -> CompilerEnv -> CS.Interface -> CYIO ()
writeInterface opts env intf@(CS.Interface m _ _)
  | optForce opts = outputInterface
  | otherwise     = do
      equal <- liftIO $ C.catch (matchInterface interfaceFile intf)
                        ignoreIOException
      unless equal outputInterface
  where
  ignoreIOException :: C.IOException -> IO Bool
  ignoreIOException _ = return False

  interfaceFile   = interfName (filePath env)
  outputInterface = liftIO $ writeModule
                    (addCurrySubdirModule (optUseSubdir opts) m interfaceFile)
                    (show $ CS.ppInterface intf)

matchInterface :: FilePath -> CS.Interface -> IO Bool
matchInterface ifn i = do
  hdl <- openFile ifn ReadMode
  src <- hGetContents hdl
  case runCYMIgnWarn (CS.parseInterface ifn src) of
    Left  _  -> hClose hdl >> return False
    Right i' -> return (i `intfEquiv` fixInterface i')

writeFlat :: Options -> CompilerEnv -> CS.Interface -> CS.Module -> IL.Module -> CYIO ()
writeFlat opts env intf mdl il = do
  when (extTarget || fcyTarget) $ do
    writeFlatCurry opts env      mdl il
    writeFlatIntf  opts env intf mdl il
  where
  extTarget = ExtendedFlatCurry `elem` optTargetTypes opts
  fcyTarget = FlatCurry         `elem` optTargetTypes opts

-- |Export an 'IL.Module' into a FlatCurry file
writeFlatCurry :: Options -> CompilerEnv -> CS.Module -> IL.Module -> CYIO ()
writeFlatCurry opts env mdl il = do
  (_, fc) <- dumpWith opts show EF.ppProg DumpFlatCurry (env, prog)
  when extTarget $ liftIO
                 $ EF.writeExtendedFlat (useSubDir $ extFlatName (filePath env)) fc
  when fcyTarget $ liftIO
                 $ EF.writeFlatCurry    (useSubDir $ flatName    (filePath env)) fc
  where
  extTarget = ExtendedFlatCurry `elem` optTargetTypes opts
  fcyTarget = FlatCurry         `elem` optTargetTypes opts
  useSubDir = addCurrySubdirModule (optUseSubdir opts) (moduleIdent env)
  prog      = genFlatCurry env mdl il

writeFlatIntf :: Options -> CompilerEnv -> CS.Interface -> CS.Module -> IL.Module -> CYIO ()
writeFlatIntf opts env intf mdl il
  | not (optInterface opts) = return ()
  | optForce opts           = outputInterface
  | otherwise               = do
      mfint <- liftIO $ EF.readFlatInterface targetFile
      let oldInterface = fromMaybe emptyIntf mfint
      when (mfint == mfint) $ return () -- necessary to close file -- TODO
      unless (oldInterface `eqInterface` fint) $ outputInterface
  where
  targetFile      = flatIntName (filePath env)
  emptyIntf       = EF.Prog "" [] [] [] []
  fint            = genFlatInterface env intf mdl il
  useSubDir       = addCurrySubdirModule (optUseSubdir opts) (moduleIdent env)
  outputInterface = liftIO $ EF.writeFlatCurry (useSubDir targetFile) fint

writeAbstractCurry :: Options -> CompEnv CS.Module -> CYIO ()
writeAbstractCurry opts (env, mdl) = do
  when acyTarget  $ liftIO
                  $ AC.writeCurry (useSubDir $ acyName (filePath env))
                  $ genTypedAbstractCurry env mdl
  when uacyTarget $ liftIO
                  $ AC.writeCurry (useSubDir $ uacyName (filePath env))
                  $ genUntypedAbstractCurry env mdl
  where
  acyTarget  = AbstractCurry        `elem` optTargetTypes opts
  uacyTarget = UntypedAbstractCurry `elem` optTargetTypes opts
  useSubDir  = addCurrySubdirModule (optUseSubdir opts) (moduleIdent env)

type Dump = (DumpLevel, CompilerEnv, String)

dumpWith :: MonadIO m
         => Options -> (a -> String) -> (a -> Doc) -> DumpLevel
         -> CompEnv a -> m (CompEnv a)
dumpWith opts rawView view lvl res@(env, mdl) = do
  let str = if dbDumpRaw (optDebugOpts opts) then rawView mdl
                                             else show (view mdl)
  doDump (optDebugOpts opts) (lvl, env, str)
  return res

-- |Translate FlatCurry into the intermediate language 'IL'
-- |The 'dump' function writes the selected information to standard output.
doDump :: MonadIO m => DebugOpts -> Dump -> m ()
doDump opts (level, env, dump)
  = when (level `elem` dbDumpLevels opts) $ liftIO $ do
      putStrLn (heading (capitalize $ lookupHeader dumpLevel) '=')
      when (dbDumpEnv opts) $ do
        putStrLn (heading "Environment" '-')
        putStrLn (showCompilerEnv env (dbDumpAllBindings opts) (dbDumpSimple opts))
      putStrLn (heading "Source Code" '-')
      putStrLn dump
  where
  heading h s = '\n' : h ++ '\n' : replicate (length h) s
  lookupHeader []            = "Unknown dump level " ++ show level
  lookupHeader ((l,_,h):lhs)
    | level == l = h
    | otherwise  = lookupHeader lhs
  capitalize = unwords . map firstUpper . words
  firstUpper ""     = ""
  firstUpper (c:cs) = toUpper c : cs

errModuleFileMismatch :: ModuleIdent -> Message
errModuleFileMismatch mid = posMessage mid $ hsep $ map text
  [ "Module", moduleName mid, "must be in a file"
  , moduleName mid ++ ".(l)curry" ]
