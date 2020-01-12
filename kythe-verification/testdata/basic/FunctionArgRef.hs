module FunctionArgRef where

-- Test simple argument reference.
-- - @a defines/binding ParamFA
f a =
    -- - @a ref ParamFA
    -- - !{ @a ref/call ParamFA }
    a

-- Test pattern-matched argument reference.
-- - @a defines/binding ParamGA
-- - @b defines/binding ParamGB
g (a,b) =
    -- TODO(robinp): odd behavior with first ref being ref/call.
    -- - !{ @a ref/call ParamGA }
    -- - @a ref ParamGA
    -- - @b ref ParamGB
    -- - @"+" ref/call _
    a + b
