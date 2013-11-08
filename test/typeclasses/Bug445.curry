-- I don't know if it's really a bug or I only don't understand records well.
-- The following gives a compiling error:

fun :: a -> Bool
fun _ = True

fun3 :: a -> a -> Bool
fun3 _ _ = False

type Rec a = { a :: a, b :: Bool }

testRecSel1 = { a := 'c', b := True } :> a

testRecSel2 x y = { a := fun x, b := fun3 y y } :> a

-- The type of the record used in testRecSel1 somehow propagates
-- to the type of the record used in testRecSel2.
-- If one comments the definition of testRecSel1 then there is no error.