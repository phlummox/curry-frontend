{- |
    Module      :  $Header$
    Description :  Generating List of Tokens and Spans
    Copyright   :  (c) 2015 - 2016, Katharina Rahf
                       2015 - 2016, Björn Peemöller
                       2015 - 2016, Jan Tikovsky

    This module defines a function for writing the list of tokens
    and spans of a Curry source module into a separate file.
-}

module TokenStream (showTokenStream) where

import Data.List             (intercalate)

import Curry.Base.Position   (Position (..))
import Curry.Base.Span       (Span (..))
import Curry.Syntax          (Token (..), Category (..), Attributes (..))

-- |Show a list of 'Span' and 'Token' tuples.
-- The list is split into one tuple on each line to increase readability.
showTokenStream :: [(Span, Token)] -> String
showTokenStream [] = "[]\n"
showTokenStream ts = "[ " ++ intercalate "\n, " (map showST filteredTs) ++ "\n]\n"
  where filteredTs     = filter (not . isVirtual) ts
        showST (sp, t) = "(" ++ showSpan sp ++ ", " ++ showToken t ++ ")"

isVirtual :: (Span, Token) -> Bool
isVirtual (_, Token cat _) = cat `elem` [EOF, VRightBrace, VSemicolon]

-- show 'span' as "((startLine, startColumn), (endLine, endColumn))"
showSpan :: Span -> String
showSpan sp = "(" ++ showPos (start sp) ++ ", " ++ showPos (end sp) ++ ")"

-- show 'Position' as "(line, column)"
showPos :: Position -> String
showPos p = "(" ++ show (line p) ++ ", " ++ show (column p) ++ ")"

-- |Show tokens and their value if needed
showToken :: Token -> String
-- literals
showToken (Token CharTok        a) = "CharTok"   +++ showAttributes a
showToken (Token IntTok         a) = "IntTok"    +++ showAttributes a
showToken (Token FloatTok       a) = "FloatTok"  +++ showAttributes a
showToken (Token StringTok      a) = "StringTok" +++ showAttributes a
-- identifiers
showToken (Token Id             a) = "Id"        +++ showAttributes a
showToken (Token QId            a) = "QId"       +++ showAttributes a
showToken (Token Sym            a) = "Sym"       +++ showAttributes a
showToken (Token QSym           a) = "QSym"      +++ showAttributes a
-- punctuation symbols
showToken (Token LeftParen      _) = "LeftParen"
showToken (Token RightParen     _) = "RightParen"
showToken (Token Semicolon      _) = "Semicolon"
showToken (Token LeftBrace      _) = "LeftBrace"
showToken (Token RightBrace     _) = "RightBrace"
showToken (Token LeftBracket    _) = "LeftBracket"
showToken (Token RightBracket   _) = "RightBracket"
showToken (Token Comma          _) = "Comma"
showToken (Token Underscore     _) = "Underscore"
showToken (Token Backquote      _) = "Backquote"
-- layout
showToken (Token VSemicolon     _) = "VSemicolon"
showToken (Token VRightBrace    _) = "VRightBrace"
-- reserved keywords
showToken (Token KW_case        _) = "KW_case"
showToken (Token KW_data        _) = "KW_data"
showToken (Token KW_do          _) = "KW_do"
showToken (Token KW_else        _) = "KW_else"
showToken (Token KW_external    _) = "KW_external"
showToken (Token KW_fcase       _) = "KW_fcase"
showToken (Token KW_foreign     _) = "KW_foreign"
showToken (Token KW_free        _) = "KW_free"
showToken (Token KW_if          _) = "KW_if"
showToken (Token KW_import      _) = "KW_import"
showToken (Token KW_in          _) = "KW_in"
showToken (Token KW_infix       _) = "KW_infix"
showToken (Token KW_infixl      _) = "KW_infixl"
showToken (Token KW_infixr      _) = "KW_infixr"
showToken (Token KW_let         _) = "KW_let"
showToken (Token KW_module      _) = "KW_module"
showToken (Token KW_newtype     _) = "KW_newtype"
showToken (Token KW_of          _) = "KW_of"
showToken (Token KW_then        _) = "KW_then"
showToken (Token KW_type        _) = "KW_type"
showToken (Token KW_where       _) = "KW_where"
-- reserved operators
showToken (Token At             _) = "At"
showToken (Token Colon          _) = "Colon"
showToken (Token DotDot         _) = "DotDot"
showToken (Token DoubleColon    _) = "DoubleColon"
showToken (Token Equals         _) = "Equals"
showToken (Token Backslash      _) = "Backslash"
showToken (Token Bar            _) = "Bar"
showToken (Token LeftArrow      _) = "LeftArrow"
showToken (Token RightArrow     _) = "RightArrow"
showToken (Token Tilde          _) = "Tilde"
-- special identifiers
showToken (Token Id_as          _) = "Id_as"
showToken (Token Id_ccall       _) = "Id_ccall"
showToken (Token Id_forall      _) = "Id_forall"
showToken (Token Id_hiding      _) = "Id_hiding"
showToken (Token Id_interface   _) = "Id_interface"
showToken (Token Id_primitive   _) = "Id_primitive"
showToken (Token Id_qualified   _) = "Id_qualified"
-- special operators
showToken (Token SymDot         _) = "SymDot"
showToken (Token SymMinus       _) = "SymMinus"
showToken (Token SymMinusDot    _) = "SymMinusDot"
-- pragmas
showToken (Token PragmaLanguage _) = "PragmaLanguage"
showToken (Token PragmaOptions  a) = "PragmaOptions" +++ showAttributes a
showToken (Token PragmaHiding   _) = "PragmaHiding"
showToken (Token PragmaEnd      _) = "PragmaEnd"
-- comments
showToken (Token LineComment    a) = "LineComment"   +++ showAttributes a
showToken (Token NestedComment  a) = "NestedComment" +++ showAttributes a
-- end-of-file token
showToken (Token EOF            _) = "EOF"

showAttributes :: Attributes -> String
showAttributes NoAttributes            = ""
showAttributes (CharAttributes    c _) = show c
showAttributes (IntAttributes     i _) = show i
showAttributes (FloatAttributes   f _) = show f
showAttributes (StringAttributes  s _) = show s
showAttributes (IdentAttributes   m i) = show $ intercalate "." (m ++ [i])
showAttributes (OptionsAttributes t a) = "(" ++ show t ++ ")" ++ ' ' : show a

-- Concatenate two 'String's with a smart space in between,
-- which is only added if both 'String's are non-empty
(+++) :: String -> String -> String
[] +++ t  = t
s  +++ [] = s
s  +++ t  = s ++ ' ' : t
