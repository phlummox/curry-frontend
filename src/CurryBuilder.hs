{- |CurryBuilder - Generates Curry representations for a Curry source file
                   including all imported modules.

    September 2005, Martin Engelke (men@informatik.uni-kiel.de)
    March 2007, extensions by Sebastian Fischer (sebf@informatik.uni-kiel.de)
    May 2011, refinements b Bjoern Peemoeller  (bjp@informatik.uni-kiel.de)
-}
module CurryBuilder (buildCurry, smake) where

import Control.Monad (liftM)
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import System.Time (ClockTime)

import Curry.Base.Ident
import Curry.Files.Filenames
import Curry.Files.PathUtils ( dropExtension, doesModuleExist, lookupCurryFile
  , getModuleModTime, tryGetModuleModTime)

import Base.Messages (status, abortWith)

import CompilerOpts (Options (..), TargetType (..))
import CurryDeps (Source (..), flatDeps)
import Modules (compileModule)

{- |Compile the Curry program 'file' including all imported modules,
    depending on the 'Options'. The compilation was successful if the
    returned list is empty, otherwise it contains error messages.
-}
buildCurry :: Options -> FilePath -> IO ()
buildCurry opts file = do
  mbFile <- lookupCurryFile (optImportPaths opts) file
  case mbFile of
    Nothing -> abortWith [missingModule file]
    Just f  -> do
      (mods, errs) <- flatDeps opts f
      if null errs
        then makeCurry (defaultToFlatCurry opts) mods f
        else abortWith errs
  where
    missingModule f      = "Error: missing module \"" ++ f ++ "\""
    defaultToFlatCurry opt
      | null $ optTargetTypes opt = opt { optTargetTypes = [FlatCurry] }
      | otherwise                 = opt

makeCurry :: Options -> [(ModuleIdent, Source)] -> FilePath -> IO ()
makeCurry opts mods targetFile = mapM_ (compile . snd) mods where
  compile (Interface _) = return ()
  compile Unknown       = return ()
  compile (Source file deps) = do
    flatIntfExists <- doesModuleExist $ flatIntName file
    if dropExtension targetFile == dropExtension file
      then if flatIntfExists && not (optForce opts) && null (optDumps opts)
              then smake (targetNames file)
                          (targetFile : mapMaybe flatInterface deps)
                          (generateFile file)
                          (skipFile file)
              else generateFile file
      else if flatIntfExists
              then smake [flatName' opts file]
                        (file : mapMaybe flatInterface deps)
                        (compileFile file)
                        (skipFile file)
              else compileFile file

  targetNames fn = [ gen fn | (tgt, gen) <- nameGens, tgt `elem` optTargetTypes opts]
    where nameGens =
            [ (FlatCurry            , flatName   )
            , (ExtendedFlatCurry    , extFlatName)
            , (FlatXml              , xmlName    )
            , (AbstractCurry        , acyName    )
            , (UntypedAbstractCurry , uacyName   )
            , (Parsed               , \ f -> fromMaybe (sourceRepName f)
                                                       (optOutput opts))
            , (FlatXml              , xmlName    )
            ]

  flatInterface mod1 = case lookup mod1 mods of
    Just (Source file _)  -> Just $ flatIntName file
    Just (Interface file) -> Just $ flatIntName file
    _                     -> Nothing

  compileFile f = do
    status opts $ "compiling " ++ f
    compileModule (compOpts True) f

  skipFile f = status opts $ "skipping " ++ f

  generateFile f = do
    status opts $ "generating " ++ head (targetNames f)
    compileModule (compOpts False) f

  compOpts isImport
    | isImport  = opts { optTargetTypes = [FlatCurry], optDumps = [] }
    | otherwise = opts


flatName' :: Options -> FilePath -> FilePath
flatName' opts
  | ExtendedFlatCurry `elem` optTargetTypes opts  = extFlatName
  | otherwise                                     = flatName

{- |A simple make function

    smake <destination files>
          <dependencies>
          <io action, if dependencies are newer than destination files>
          <io action, if destination files are newer than dependencies>
-}
smake :: [FilePath] -> [FilePath] -> IO a -> IO a -> IO a
smake dests deps cmd alt = do
  destTimes <- getDestTimes dests
  depTimes  <- getDepTimes deps
  abortOnError $ make destTimes depTimes
  where
  make destTimes depTimes
    | length destTimes < length dests = cmd
    | null depTimes                   = abortWith ["unknown dependencies"]
    | outOfDate destTimes depTimes    = cmd
    | otherwise                       = alt

getDestTimes :: [FilePath] -> IO [ClockTime]
getDestTimes = liftM catMaybes . mapM tryGetModuleModTime

getDepTimes :: [String] -> IO [ClockTime]
getDepTimes = mapM (abortOnError . getModuleModTime)

outOfDate :: [ClockTime] -> [ClockTime] -> Bool
outOfDate tgtimes dptimes = or [ tg < dp | tg <- tgtimes, dp <- dptimes]

abortOnError :: IO a -> IO a
abortOnError act = catch act (\ err -> abortWith [show err])
