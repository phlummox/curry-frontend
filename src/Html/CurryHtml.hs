{- |
    Module      :  $Header$
    Description :  Generating HTML documentation
    Copyright   :  (c) 2011 - 2016, Björn Peemöller
                       2016       , Jan Tikovsky
    License     :  OtherLicense

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

    This module defines a function for generating HTML documentation pages
    for Curry source modules.
-}
module Html.CurryHtml (source2html) where

import Control.Monad.Writer
import Data.List             (mapAccumL)
import Data.Maybe            (fromMaybe, isJust)
import Network.URI           (escapeURIString, isUnreserved)
import System.Directory      (copyFile, doesFileExist)
import System.FilePath       ((</>))

import Curry.Base.Ident      ( ModuleIdent (..), Ident (..), QualIdent (..)
                             , unqualify, moduleName)
import Curry.Base.Monad      (CYIO, failMessages)
import Curry.Base.Position   (Position)
import Curry.Base.Pretty     ((<+>), text, vcat)
import Curry.Files.Filenames (htmlName)
import Curry.Syntax          (Module (..), Token)

import Html.SyntaxColoring

import Base.Messages         (message)
import CompilerOpts          (Options (..))
import Paths_curry_frontend  (getDataFileName)

-- |'FilePath' of the CSS style file to be added to the documentation.
cssFile :: FilePath
cssFile = "currysource.css"

-- |Translate source file into HTML file with syntaxcoloring
source2html :: Options -> ModuleIdent -> [(Position, Token)] -> Module -> CYIO ()
source2html opts mid toks mdl = do
  liftIO $ writeFile (outDir </> htmlName mid) doc
  updateCSSFile outDir
  where
  doc    = program2html mid (genProgram mdl toks)
  outDir = fromMaybe "." (optHtmlDir opts)

-- |Update the CSS file
updateCSSFile :: FilePath -> CYIO ()
updateCSSFile dir = do
  src <- liftIO $ getDataFileName cssFile
  let target = dir </> cssFile
  srcExists <- liftIO $ doesFileExist src
  if srcExists then liftIO $ copyFile src target
               else failMessages [message $ missingStyleFile src]
  where
  missingStyleFile f = vcat
    [ text "Could not copy CSS style file:"
    , text "File" <+> text ("`" ++ f ++ "'") <+> text "does not exist"
    ]

-- generates htmlcode with syntax highlighting
-- @param modulname
-- @param a program
-- @return HTMLcode
program2html :: ModuleIdent -> [Code] -> String
program2html m codes = unlines
  [ "<!DOCTYPE html>"
  , "<html>", "<head>"
  , "<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\" />"
  , "<title>" ++ titleHtml ++ "</title>"
  , "<link rel=\"stylesheet\" type=\"text/css\" href=\"" ++ cssFile ++ "\"/>"
  , "</head>"
  , "<body>"
  , "<table><tbody><tr>"
  , "<td class=\"linenumbers\"><pre>" ++ lineHtml ++ "</pre></td>"
  , "<td class=\"sourcecode\"><pre>" ++ codeHtml ++ "</pre></td>"
  , "</tr></tbody></table>"
  , "</body>"
  , "</html>"
  ]
  where
  titleHtml = "Module " ++ moduleName m
  lineHtml  = unlines $ map show [1 .. length (lines codeHtml)]
  codeHtml  = concat $ snd $ mapAccumL (code2html m) [] codes

code2html :: ModuleIdent -> [QualIdent] -> Code -> ([QualIdent], String)
code2html m defs c
  | isCall c  = (defs, maybe tag (addEntityLink m tag) (getQualIdent c))
  | isDecl c  = case getQualIdent c of
      Just i | i `notElem` defs
        -> (i:defs, spanTag (code2class c) (escIdent i) (escCode c))
      _ -> (defs, tag)
  | otherwise = case c of
      ModuleName m' -> (defs, addModuleLink m m' tag)
      _             -> (defs, tag)
  where tag = spanTag (code2class c) "" (escCode c)

escCode :: Code -> String
escCode = htmlQuote . code2string

escIdent :: QualIdent -> String
escIdent = htmlQuote . idName . unqualify

spanTag :: String -> String -> String -> String
spanTag clV idV str
  | null clV && null idV = str
  | otherwise            = "<span" ++ codeclass ++ idValue ++ ">"
                           ++ str ++ "</span>"
  where
  codeclass = if null clV then "" else " class=\"" ++ clV ++ "\""
  idValue   = if null idV then "" else " id=\"" ++ idV ++ "\""

-- which code has which css class
-- @param code
-- @return css class of the code
code2class :: Code -> String
code2class (Space          _) = ""
code2class NewLine            = ""
code2class (Keyword        _) = "keyword"
code2class (Pragma         _) = "pragma"
code2class (Symbol         _) = "symbol"
code2class (TypeCons   _ _ _) = "type"
code2class (DataCons   _ _ _) = "cons"
code2class (Function   _ _ _) = "func"
code2class (Identifier _ _ _) = "ident"
code2class (ModuleName     _) = "module"
code2class (Commentary     _) = "comment"
code2class (NumberCode     _) = "number"
code2class (StringCode     _) = "string"
code2class (CharCode       _) = "char"

addModuleLink :: ModuleIdent -> ModuleIdent -> String -> String
addModuleLink m m' str
  = "<a href=\"" ++ makeRelativePath m m' ++ "\">" ++ str ++ "</a>"

addEntityLink :: ModuleIdent -> String -> QualIdent -> String
addEntityLink m str qid =
  "<a href=\"" ++ modPath ++ "#" ++ fragment  ++ "\">" ++ str ++ "</a>"
  where
  modPath       = maybe "" (makeRelativePath m) mmid
  fragment      = string2urlencoded (idName ident)
  (mmid, ident) = (qidModule qid, qidIdent qid)

makeRelativePath :: ModuleIdent -> ModuleIdent -> String
makeRelativePath cur new  | cur == new = ""
                          | otherwise  = htmlName new

isCall :: Code -> Bool
isCall (TypeCons   TypeExport _ _) = True
isCall (TypeCons   TypeImport _ _) = True
isCall (TypeCons   TypeRefer  _ _) = True
isCall (TypeCons   _          _ _) = False
isCall (Identifier _          _ _) = False
isCall c                       = not (isDecl c) && isJust (getQualIdent c)

isDecl :: Code -> Bool
isDecl (DataCons ConsDeclare _ _) = True
isDecl (Function FuncDeclare _ _) = True
isDecl (TypeCons TypeDeclare _ _) = True
isDecl _                          = False

-- Translates arbitrary strings into equivalent urlencoded string.
string2urlencoded :: String -> String
string2urlencoded = escapeURIString isUnreserved

htmlQuote :: String -> String
htmlQuote [] = []
htmlQuote (c : cs)
  | c == '<'  = "&lt;"    ++ htmlQuote cs
  | c == '>'  = "&gt;"    ++ htmlQuote cs
  | c == '&'  = "&amp;"   ++ htmlQuote cs
  | c == '"'  = "&quot;"  ++ htmlQuote cs
  | c == 'ä'  = "&auml;"  ++ htmlQuote cs
  | c == 'ö'  = "&ouml;"  ++ htmlQuote cs
  | c == 'ü'  = "&uuml;"  ++ htmlQuote cs
  | c == 'Ä'  = "&Auml;"  ++ htmlQuote cs
  | c == 'Ö'  = "&Ouml;"  ++ htmlQuote cs
  | c == 'Ü'  = "&Uuml;"  ++ htmlQuote cs
  | c == 'ß'  = "&szlig;" ++ htmlQuote cs
  | otherwise = c : htmlQuote cs
