-- |
-- This module provides basic inlining capabilities
--
module Language.PureScript.CodeGen.Erl.Optimizer.Inliner
  ( inlineCommonValues
  , inlineCommonOperators
  , evaluateIifes
  , etaConvert
  )
  where

import Prelude.Compat

import Data.Text (Text)
import Data.String (IsString)
import Language.PureScript.PSString (PSString)

import Language.PureScript.CodeGen.Erl.AST
import Language.PureScript.CodeGen.Erl.Optimizer.Common
import qualified Language.PureScript.Constants as C
import qualified Language.PureScript.CodeGen.Erl.Constants as EC

shouldInline :: Erl -> Bool
shouldInline (EVar _) = True
shouldInline _ = False

etaConvert :: Erl -> Erl
etaConvert = everywhereOnErl convert
  where
    convert :: Erl -> Erl
    -- TODO ported from JS, but this seems to be beta-reduction and the iife below is eta...?
    convert (EApp (EFun _ x e) [arg])
      | shouldInline arg
      , arg /= EVar x
      , not (isRebound x e)
      , not (isReboundE arg e) = replaceIdents [(x, arg)] e
    convert e = e

    isReboundE (EVar x) e = isRebound x e
    isReboundE _ _ = False

-- -- fun (X) -> fun {body} end(X) end  --> fun {body} end
evaluateIifes :: Erl -> Erl
evaluateIifes = everywhereOnErl convert
  where
  convert :: Erl -> Erl
  convert (EFun Nothing x (EApp fun@EFunFull{} [EVar x'])) | x == x', not (occurs x fun) = fun
  convert e = e

inlineCommonValues :: Erl -> Erl
inlineCommonValues = everywhereOnErl convert
  where
  convert :: Erl -> Erl
  convert = id
--   convert (JSApp ss fn [dict])
--     | isDict' [semiringNumber, semiringInt] dict && isFn fnZero fn = JSNumericLiteral ss (Left 0)
--     | isDict' [semiringNumber, semiringInt] dict && isFn fnOne fn = JSNumericLiteral ss (Left 1)
--     | isDict boundedBoolean dict && isFn fnBottom fn = JSBooleanLiteral ss False
--     | isDict boundedBoolean dict && isFn fnTop fn = JSBooleanLiteral ss True
--   convert (JSApp ss (JSApp _ (JSApp _ fn [dict]) [x]) [y])
--     | isDict semiringInt dict && isFn fnAdd fn = intOp ss Add x y
--     | isDict semiringInt dict && isFn fnMultiply fn = intOp ss Multiply x y
--     | isDict euclideanRingInt dict && isFn fnDivide fn = intOp ss Divide x y
--     | isDict ringInt dict && isFn fnSubtract fn = intOp ss Subtract x y
--   convert other = other
--   fnZero = (C.dataSemiring, C.zero)
--   fnOne = (C.dataSemiring, C.one)
--   fnBottom = (C.dataBounded, C.bottom)
--   fnTop = (C.dataBounded, C.top)
--   fnAdd = (C.dataSemiring, C.add)
--   fnDivide = (C.dataEuclideanRing, C.div)
--   fnMultiply = (C.dataSemiring, C.mul)
--   fnSubtract = (C.dataRing, C.sub)
--   intOp ss op x y = JSBinary ss BitwiseOr (JSBinary ss op x y) (JSNumericLiteral ss (Left 0))
--
inlineCommonOperators :: Erl -> Erl
inlineCommonOperators = applyAll
  [ binary semiringNumber opAdd Add
  , binary semiringNumber opMul Multiply
  , binary ringNumber opSub Subtract
  , unary  ringNumber opNegate Negate
  , binary semiringInt opAdd Add
  , binary semiringInt opMul Multiply
  , binary ringInt opSub Subtract
  , unary  ringInt opNegate Negate

  , binary euclideanRingNumber opDiv FDivide

  , binary eqNumber opEq IdenticalTo
  , binary eqNumber opNotEq NotIdenticalTo
  , binary eqInt opEq IdenticalTo
  , binary eqInt opNotEq NotIdenticalTo
  , binary eqString opEq IdenticalTo
  , binary eqString opNotEq NotIdenticalTo
  , binary eqChar opEq IdenticalTo
  , binary eqChar opNotEq NotIdenticalTo
  , binary eqBoolean opEq IdenticalTo
  , binary eqBoolean opNotEq NotIdenticalTo

  , binary ordBoolean opLessThan LessThan
  , binary ordBoolean opLessThanOrEq LessThanOrEqualTo
  , binary ordBoolean opGreaterThan GreaterThan
  , binary ordBoolean opGreaterThanOrEq GreaterThanOrEqualTo
  , binary ordChar opLessThan LessThan
  , binary ordChar opLessThanOrEq LessThanOrEqualTo
  , binary ordChar opGreaterThan GreaterThan
  , binary ordChar opGreaterThanOrEq GreaterThanOrEqualTo
  , binary ordInt opLessThan LessThan
  , binary ordInt opLessThanOrEq LessThanOrEqualTo
  , binary ordInt opGreaterThan GreaterThan
  , binary ordInt opGreaterThanOrEq GreaterThanOrEqualTo
  , binary ordNumber opLessThan LessThan
  , binary ordNumber opLessThanOrEq LessThanOrEqualTo
  , binary ordNumber opGreaterThan GreaterThan
  , binary ordNumber opGreaterThanOrEq GreaterThanOrEqualTo
  , binary ordString opLessThan LessThan
  , binary ordString opLessThanOrEq LessThanOrEqualTo
  , binary ordString opGreaterThan GreaterThan
  , binary ordString opGreaterThanOrEq GreaterThanOrEqualTo

  , binary heytingAlgebraBoolean opConj And
  , binary heytingAlgebraBoolean opDisj Or
  , unary  heytingAlgebraBoolean opNot Not

  , inlineNonClassFunction (isModFn (EC.dataFunction, C.apply)) $ \f x -> EApp f [x]
  , inlineNonClassFunction (isModFn (EC.dataFunction, C.applyFlipped)) $ \x f -> EApp f [x]
  ]
--   , inlineNonClassFunction (isModFnWithDict (C.dataArray, C.unsafeIndex)) $ flip (JSIndexer Nothing)
--   ] ++
--   [ fn | i <- [0..10], fn <- [ mkFn i, runFn i ] ]
  where
  binary ::  (Text, PSString) -> (Text, PSString) -> BinaryOperator -> Erl -> Erl
  binary dict fns op = everywhereOnErl convert
    where
    convert :: Erl -> Erl
    convert (EApp fn [dict', x, y]) | isDict dict dict' && isUncurriedFn fns fn = EBinary op x y
    convert other = other

  unary ::  (Text, PSString) -> (Text, PSString) -> UnaryOperator -> Erl -> Erl
  unary dicts fns op = everywhereOnErl convert
    where
    convert :: Erl -> Erl
    convert (EApp (EApp fn [dict']) [x]) | isDict dicts dict' && isDict fns fn = EUnary op x
    convert other = other

  inlineNonClassFunction :: (Erl -> Bool) -> (Erl -> Erl -> Erl) -> Erl -> Erl
  inlineNonClassFunction p f = everywhereOnErl convert
    where
    convert :: Erl -> Erl
    convert (EApp (EApp op' [x]) [y]) | p op' = f x y
    convert other = other

  isModFn :: (Text, Text) -> Erl -> Bool
  isModFn = isFn

semiringNumber :: forall a b. (IsString a, IsString b) => (a, b)
semiringNumber = (EC.dataSemiring, C.semiringNumber)

semiringInt :: forall a b. (IsString a, IsString b) => (a, b)
semiringInt = (EC.dataSemiring, C.semiringInt)

ringNumber :: forall a b. (IsString a, IsString b) => (a, b)
ringNumber = (EC.dataRing, C.ringNumber)

ringInt :: forall a b. (IsString a, IsString b) => (a, b)
ringInt = (EC.dataRing, C.ringInt)

euclideanRingNumber :: forall a b. (IsString a, IsString b) => (a, b)
euclideanRingNumber = (EC.dataEuclideanRing, C.euclideanRingNumber)

eqNumber :: forall a b. (IsString a, IsString b) => (a, b)
eqNumber = (EC.dataEq, C.eqNumber)

eqInt :: forall a b. (IsString a, IsString b) => (a, b)
eqInt = (EC.dataEq, C.eqInt)

eqString :: forall a b. (IsString a, IsString b) => (a, b)
eqString = (EC.dataEq, C.eqString)

eqChar :: forall a b. (IsString a, IsString b) => (a, b)
eqChar = (EC.dataEq, C.eqChar)

eqBoolean :: forall a b. (IsString a, IsString b) => (a, b)
eqBoolean = (EC.dataEq, C.eqBoolean)

ordBoolean :: forall a b. (IsString a, IsString b) => (a, b)
ordBoolean = (EC.dataOrd, C.ordBoolean)

ordNumber :: forall a b. (IsString a, IsString b) => (a, b)
ordNumber = (C.dataOrd, C.ordNumber)

ordInt :: forall a b. (IsString a, IsString b) => (a, b)
ordInt = (EC.dataOrd, C.ordInt)

ordString :: forall a b. (IsString a, IsString b) => (a, b)
ordString = (EC.dataOrd, C.ordString)

ordChar :: forall a b. (IsString a, IsString b) => (a, b)
ordChar = (EC.dataOrd, C.ordChar)

-- semigroupString :: forall a b. (IsString a, IsString b) => (a, b)
-- semigroupString = (EC.dataSemigroup, C.semigroupString)

-- boundedBoolean :: forall a b. (IsString a, IsString b) => (a, b)
-- boundedBoolean = (EC.dataBounded, C.boundedBoolean)

heytingAlgebraBoolean :: forall a b. (IsString a, IsString b) => (a, b)
heytingAlgebraBoolean = (EC.dataHeytingAlgebra, C.heytingAlgebraBoolean)

-- semigroupoidFn :: forall a b. (IsString a, IsString b) => (a, b)
-- semigroupoidFn = (EC.controlSemigroupoid, C.semigroupoidFn)

opAdd :: forall a b. (IsString a, IsString b) => (a, b)
opAdd = (EC.dataSemiring, C.add)

opMul :: forall a b. (IsString a, IsString b) => (a, b)
opMul = (EC.dataSemiring, C.mul)

opEq :: forall a b. (IsString a, IsString b) => (a, b)
opEq = (EC.dataEq, C.eq)

opNotEq :: forall a b. (IsString a, IsString b) => (a, b)
opNotEq = (EC.dataEq, C.notEq)

opLessThan :: forall a b. (IsString a, IsString b) => (a, b)
opLessThan = (EC.dataOrd, C.lessThan)

opLessThanOrEq :: forall a b. (IsString a, IsString b) => (a, b)
opLessThanOrEq = (EC.dataOrd, C.lessThanOrEq)

opGreaterThan :: forall a b. (IsString a, IsString b) => (a, b)
opGreaterThan = (EC.dataOrd, C.greaterThan)

opGreaterThanOrEq :: forall a b. (IsString a, IsString b) => (a, b)
opGreaterThanOrEq = (EC.dataOrd, C.greaterThanOrEq)

-- opAppend :: forall a b. (IsString a, IsString b) => (a, b)
-- opAppend = (EC.dataSemigroup, C.append)

opSub :: forall a b. (IsString a, IsString b) => (a, b)
opSub = (EC.dataRing, C.sub)

opNegate :: forall a b. (IsString a, IsString b) => (a, b)
opNegate = (EC.dataRing, C.negate)

opDiv :: forall a b. (IsString a, IsString b) => (a, b)
opDiv = (EC.dataEuclideanRing, C.div)

opConj :: forall a b. (IsString a, IsString b) => (a, b)
opConj = (EC.dataHeytingAlgebra, C.conj)

opDisj :: forall a b. (IsString a, IsString b) => (a, b)
opDisj = (EC.dataHeytingAlgebra, C.disj)

opNot :: forall a b. (IsString a, IsString b) => (a, b)
opNot = (EC.dataHeytingAlgebra, C.not)