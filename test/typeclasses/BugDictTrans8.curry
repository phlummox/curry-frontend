

class A a where
  funA :: a -> a

class B a where
  funB :: a -> a


{-
test2 z = z
  where test1_1 x = funA x
        test1_2 x = funB x
        test1_3 x = funA z
          where test_1_3_1 x = funA x
                test_1_3_2 x = funB x
                test_1_3_3 x = funA z
                -}



test2 z = z
  where test2_1 x = funA z

  