-- Copyright 2017 Google Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{-# LANGUAGE LambdaCase #-}
module Language.Haskell.Indexer.Backend.Ghc.Test.TranslateAssert
    ( checking
    , assertAll
    , debugAll
    , prettyReference
    --
    , funk, bind2
    --
    , declsAt, declAt
    , docUriDecl
    , moduleDocUriDecl
    --
    , usages, singleUsage
    , docUriDeclUsages, singleDocUriDeclUsage
    , moduleDocUriDeclImports, singleModuleDocUriDeclImport
    --
    , includesPos, spanIs
    , refKindIs, refContextIs
    , userFriendlyTypeIs
    , hasRelation
    , declPropEquals
    , importAt
    --
    , extraMethodForInstanceIs
    , extraAlternateIdSpanContainsPos
    -- * Reexports.
    , module Language.Haskell.Indexer.Translate
    ) where

import Control.Monad (join, liftM2, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT(..), ask, asks)
import Control.Monad.IO.Class (MonadIO, liftIO)

import Language.Haskell.Indexer.Translate

import Data.Foldable (sequenceA_)
import qualified Data.List as L
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T

import Test.HUnit ((@?), assertFailure)

debugAll :: ReaderT XRef IO ()
debugAll = ask >>= (liftIO . print)

-- | Returns the declarations that include the given position, sorted by
-- tickstring. TODO(robinpalotai): change this to sort on unqualified id?
-- Fails if there aren't any decls.
-- Note: this doesn't consider the file, so there might be conflicts
-- if multiple files are processed. Use only for tests where a single file
-- is loaded, or explicitly test the file of the returned Decl.
declsAt :: (Int,Int) -> ReaderT XRef IO [Decl]
declsAt pos = do
    decls <- asks xrefDecls
    let filtered = filter (containsPos pos) decls
    liftIO $ not (null filtered) @? concat
        [ "No declarations at pos ", show pos ]
    return $! L.sortBy (comparing declTick) filtered

-- | Returns the single declaration around the given position.
-- Fails if there isn't exactly one declaration.
declAt :: (Int,Int) -> ReaderT XRef IO Decl
declAt pos = declsAt pos >>= \case
    [] -> error "declsAt should have caught empty decls"
    [d] -> return d
    ds -> failConcat
        [ "Multiple declarations at pos ", show pos
        , ":\n", prettyDecls ds
        ]

docUriDecls :: T.Text -> ReaderT XRef IO [DocUriDecl]
docUriDecls uri = do
    decls <- asks xrefDocDecls
    let filtered = filter ((== uri) . ddeclDocUri) decls
    liftIO $ not (null filtered) @? concat
        [ "No declarations with doc/uri ", T.unpack uri]
    return $! L.sortBy (comparing ddeclTick) filtered

docUriDecl :: T.Text -> ReaderT XRef IO DocUriDecl
docUriDecl uri = docUriDecls uri >>= \case
    [] -> error "docUriDecls should have caught empty decls"
    [d] -> return d
    ds -> failConcat
        [ "Multiple declarations with doc/uri ", T.unpack uri
        , ":\n", prettyDocUriDecls ds
        ]

moduleDocUriDecls :: T.Text -> ReaderT XRef IO [ModuleDocUriDecl]
moduleDocUriDecls uri = do
    decls <- asks xrefModuleDocDecls
    let filtered = filter ((== uri) . mddeclDocUri) decls
    liftIO $ not (null filtered) @? concat
        [ "No module declarations with doc/uri ", T.unpack uri]
    return $! L.sortBy (comparing mddeclTick) filtered

moduleDocUriDecl :: T.Text -> ReaderT XRef IO ModuleDocUriDecl
moduleDocUriDecl uri = moduleDocUriDecls uri >>= \case
    [] -> error "moduleDocUriDecls should have caught empty decls"
    [d] -> return d
    ds -> failConcat
        [ "Multiple module declarations with doc/uri ", T.unpack uri
        , ":\n", prettyModuleDocUriDecls ds
        ]

prettySpan :: Span -> String
prettySpan (Span (Pos l1 c1 _) (Pos l2 c2 _)) = concat
    [ "("
    , show l1, ":", show c1
    , ","
    , show l2, ":", show c2
    , ")"
    ]

prettyMaybeSpan :: Maybe Span -> String
prettyMaybeSpan Nothing = "<no span>"
prettyMaybeSpan (Just s) = prettySpan s

prettyDecls :: [Decl] -> String
prettyDecls ds = L.intercalate "\n" (map prettyDecl ds) ++ "\n"

prettyDecl :: Decl -> String
prettyDecl decl = "Decl { name: " ++ show (tickThing $ declTick decl)
                  ++ ", type: " ++ show (declQualifiedType $ declType decl)
                                 ++ pos
                  ++ ", extra: " ++ show (declExtra decl)
                                 ++ "}"
  where
    pos = case declIdentifierSpan decl of
        Just s -> ", pos: " ++ prettySpan s
        Nothing   -> ""

prettyDocUriDecls :: [DocUriDecl] -> String
prettyDocUriDecls ds = L.intercalate "\n" (map prettyDocUriDecl ds) ++ "\n"

prettyDocUriDecl :: DocUriDecl -> String
prettyDocUriDecl decl =
    concat
        [ "DocUriDecl { name: ",
          show (tickThing $ ddeclTick decl),
          ", doc/uri: ",
          show (ddeclDocUri decl),
          "}"
        ]

prettyModuleDocUriDecls :: [ModuleDocUriDecl] -> String
prettyModuleDocUriDecls ds = L.intercalate "\n" (map prettyModuleDocUriDecl ds) ++ "\n"

prettyModuleDocUriDecl :: ModuleDocUriDecl -> String
prettyModuleDocUriDecl decl =
    concat
        [ "ModuleDocUriDecl { module: ",
          show (mtPkgModule $ mddeclTick decl),
          ", doc/uri: ",
          show (mddeclDocUri decl),
          "}"
        ]

prettyReference :: TickReference -> String
prettyReference ref = "TickReference {"
                   ++ ", pos: " ++ prettySpan (refSourceSpan ref)
                   ++ "}"

prettyModuleTick :: ModuleTick -> String
prettyModuleTick mt = "ModuleTick {"
                   ++ ", pos: " ++ prettyMaybeSpan (mtSpan mt)
                   ++ "}"

-- | Returns the module imports that include the given position.
-- Fails if there aren't any imports, or there are multiple imports.
-- Note: this doesn't consider the file, so there might be conflicts
-- if multiple files are processed. Use only for tests where a single file
-- is loaded, or explicitly test the file of the returned Import.
importAt :: (Int,Int) -> Text -> ReaderT XRef IO ()
importAt pos importName = do
    imports <- asks xrefImports
    let filtered = filter equalsImport imports
    case filtered of
        [] -> failConcat ["No import ", T.unpack importName, " at pos ", show pos]
        [_im] -> return ()
        ims -> failConcat
            ["Multiple imports at pos ", show pos, ":\n", show ims]
    where
      equalsImport :: ModuleTick -> Bool
      equalsImport imp =
          containsPos pos imp && importName == (getModule . mtPkgModule $ imp)

containsPos :: (Spanny a) => (Int,Int) -> a -> Bool
containsPos pos a = case spanOf a of
    Just (Span (Pos lineStart colStart _) (Pos lineEnd colEnd _)) ->
        (lineStart, colStart) <= pos && pos < (lineEnd, colEnd)
    _ -> False

-- | Returns usages of a given declaration in span-sorted order.
-- Fails if no usages found.
usages :: Decl -> ReaderT XRef IO [TickReference]
usages decl = do
    res <- filter ((== declTick decl) . refTargetTick) <$> asks xrefCrossRefs
    liftIO $ not (null res) @? concat
        [ "No usages found for decl ", prettyDecl decl ]
    return $! L.sortBy (comparing refSourceSpan) res

-- | Returns the single usage of the given declaration.
-- Fails if there isn't exactly one usage.
singleUsage :: Decl -> ReaderT XRef IO TickReference
singleUsage decl = usages decl >>= \case
    [] -> error "usages should have caught empty usages"
    [u] -> return u
    us -> failConcat
        [ "Multiple usages of decl ", prettyDecl decl
        , ":\n", L.intercalate "\n" $ map prettyReference us
        ]

-- | Returns usages of a given declaration in span-sorted order.
-- Fails if no usages found.
docUriDeclUsages :: DocUriDecl -> ReaderT XRef IO [TickReference]
docUriDeclUsages decl = do
    res <- filter ((== ddeclTick decl) . refTargetTick) <$> asks xrefCrossRefs
    liftIO $ not (null res) @? concat
        [ "No usages found for decl ", prettyDocUriDecl decl ]
    return $! L.sortBy (comparing refSourceSpan) res

-- | Returns the single usage of the given declaration.
-- Fails if there isn't exactly one usage.
singleDocUriDeclUsage :: DocUriDecl -> ReaderT XRef IO TickReference
singleDocUriDeclUsage decl = docUriDeclUsages decl >>= \case
    [] -> error "usages should have caught empty usages"
    [u] -> return u
    us -> failConcat
        [ "Multiple usages of decl ", prettyDocUriDecl decl
        , ":\n", L.intercalate "\n" $ map prettyReference us
        ]

-- | Returns usages of a given module declaration in span-sorted order.
-- Fails if no usages found.
moduleDocUriDeclImports :: ModuleDocUriDecl -> ReaderT XRef IO [ModuleTick]
moduleDocUriDeclImports decl = do
    res <- filter (== mddeclTick decl) <$> asks xrefImports
    liftIO $ not (null res) @? concat
          ["No usages found for module decl ", prettyModuleDocUriDecl decl]
    return $! L.sortBy (comparing mtSpan) res

-- | Returns the single usage of the given module declaration.
-- Fails if there isn't exactly one usage.
singleModuleDocUriDeclImport :: ModuleDocUriDecl -> ReaderT XRef IO ModuleTick
singleModuleDocUriDeclImport decl = moduleDocUriDeclImports decl >>= \case
    [] -> error "usages should have caught empty usages"
    [u] -> return u
    us -> failConcat
        [ "Multiple usages of module decl ", prettyModuleDocUriDecl decl
        , ":\n", L.intercalate "\n" $ map prettyModuleTick us
        ]

-- | Asserts that the given thing's span includes the given position.
includesPos :: (Show a, Spanny a, MonadIO m) => (Int,Int) -> a -> m ()
includesPos pos a = unless (containsPos pos a) $ failConcat
    [ "Span of ", show a, " doesn't include ", show pos ]

-- | Asserts that the given thing's span matches the given closed-open range.
spanIs :: (Show a, Spanny a, MonadIO m) => (Int,Int) -> (Int, Int) -> a -> m ()
spanIs s e a = case spanOf a of
    Just (Span (Pos l1 c1 _) (Pos l2 c2 _))
        | s == (l1, c1) && e == (l2, c2)    -> return ()
        | otherwise -> failConcat
            [ "Span of ", show a, " is ", show (spanOf a)
            , " instead ", show (s,e)
            ]
    _ -> failConcat ["No span for ", show a]

refKindIs :: (MonadIO m) => ReferenceKind -> TickReference -> m ()
refKindIs k tr = unless (refKind tr == k) $ failConcat
    [ "Reference kind of ", prettyReference tr, " is not ", show k]

hasRelation :: RelationKind -> Decl -> Decl -> ReaderT XRef IO ()
hasRelation k s t = do
    let sought = Relation (declTick s) k (declTick t)
    rels <- asks xrefRelations
    unless (sought `elem` rels) $ failConcat
        [ "Relation ", show sought, " was not found." ]

-- | Asserts that the high-level reference context of a given reference points
-- to the given declaration.
refContextIs :: (MonadIO m) => Decl -> TickReference -> m ()
refContextIs decl tr =
    unless (refHighLevelContext tr == Just (declTick decl)) $ failConcat
        [ "Reference context of ", prettyReference tr, " doesn't match ", prettyDecl decl
        , " having tick ", show (declTick decl)
        , ", instead matches ", show (refHighLevelContext tr)
        ]

userFriendlyTypeIs :: (MonadIO m) => Text -> Decl -> m ()
userFriendlyTypeIs t decl =
    unless (declUserFriendlyType (declType decl) == t) $ failConcat
        [ "User-friendly type of ", prettyDecl decl, " doesn't match ", show t ]

extraMethodForInstanceIs :: (MonadIO m) => Text -> Decl -> m ()
extraMethodForInstanceIs t decl =
    let emi = declExtra decl >>= methodForInstance
    in unless (emi == Just t) $ failConcat
          [ "methodForInstance of ", prettyDecl decl, " doesn't match ", show t ]

extraAlternateIdSpanContainsPos :: (MonadIO m) => (Int, Int) -> Decl -> m ()
extraAlternateIdSpanContainsPos p decl =
    let idSpan = declExtra decl >>= alternateIdSpan
    in unless ((containsPos p <$> idSpan) == Just True) $ failConcat
          [ "alternateIdSpan of ", prettyDecl decl, " doesn't contain pas ", show p ]

-- | Sugar for asserting some property of a Decl, for one-off tests.
-- Frequent usages should have a proper specific function in this module
-- instead.
declPropEquals :: (MonadIO m, Eq a, Show a) => (Decl -> a) -> a -> Decl -> m ()
declPropEquals f expected decl =
    let prop = f decl
    in unless (prop == expected) $ failConcat
          [ "Expected decl property ", show prop
          , " doesn't match ", show expected
          , " for decl ", prettyDecl decl
          ]

-- | Renamed and specialized reexport for convenience.
checking :: (Monad m) => m () -> ReaderT XRef m ()
checking = lift

-- | Performs all assertions on the same subject.
assertAll :: (Monad m) => [a -> m ()] -> a -> m ()
assertAll = runReaderT . sequenceA_ . map ReaderT

-- | Combinator with no better name?
funk :: (Monad m) => (a -> b -> m c) -> m a -> b -> m c
funk f m b = m >>= flip f b

bind2 :: (Monad m) => (a -> b -> m c) -> m a -> m b -> m c
bind2 f ma mb = join (liftM2 f ma mb)

-- Internal helpers.

failConcat :: (MonadIO m) => [String] -> m a
failConcat ss = (liftIO . assertFailure . concat) ss >> return undefined

class Spanny a where
    spanOf :: a -> Maybe Span

instance Spanny Span where
    spanOf = Just

instance Spanny Decl where
    spanOf = declIdentifierSpan

instance Spanny TickReference where
    spanOf = Just . refSourceSpan

instance Spanny ModuleTick where
    spanOf = mtSpan
