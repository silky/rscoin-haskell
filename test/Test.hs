import           Control.Concurrent.STM (atomically, writeTVar)
import           Spec                   (spec)
import           Test.Hspec             (hspec)

import qualified TestOptions            as Opts

main :: IO ()
main = do
    testConfig <- Opts.readTestConfig "test.yaml"
    atomically $ writeTVar Opts.testTVar testConfig
    hspec spec
