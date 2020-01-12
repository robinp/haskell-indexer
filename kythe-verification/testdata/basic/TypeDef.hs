module TypeDef where

-- See https://kythe.io/docs/schema/#completes

-- - @add defines/binding FunDecl
-- - FunDecl.complete complete
add :: Int -> Int -> Int
-- - !{ @add defines/binding FunDecl }
-- - @add defines/binding FunAdd
-- - FunAdd.complete definition
-- - @add completes FunDecl
add x y = x + y
