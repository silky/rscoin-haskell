{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators   #-}

import           Control.Concurrent         (threadDelay)
import           Control.Concurrent.Async   (forConcurrently)
import           Data.ByteString            (ByteString)
import           Data.Maybe                 (fromMaybe)
import qualified Data.Text.IO               as TIO
import           Formatting                 (build, fixed, int, sformat, stext,
                                             (%))
import           System.IO.Temp             (withSystemTempDirectory)

-- workaround to make stylish-haskell work :(
import           Options.Generic

import           Serokell.Util.Text         (show')

import           RSCoin.Core                (Severity (..), bankSecretKey,
                                             finishPeriod, initLogging)
import           RSCoin.Timed               (runRealMode)
import           RSCoin.User.Wallet         (UserAddress)

import           Bench.RSCoin.FilePathUtils (tempBenchDirectory)
import           Bench.RSCoin.Logging       (initBenchLogger, logInfo)
import           Bench.RSCoin.UserLogic     (benchUserTransactions,
                                             initializeBank, initializeUser,
                                             userThread)
import           Bench.RSCoin.Util          (ElapsedTime (elapsedWallTime),
                                             measureTime_, perSecond)

data BenchOptions = BenchOptions
    { users         :: Int            <?> "number of users"
    , transactions  :: Maybe Word     <?> "number of transactions per user"
    , severity      :: Maybe Severity <?> "severity for global logger"
    , benchSeverity :: Maybe Severity <?> "severity for bench logger"
    , bank          :: ByteString     <?> "bank host"
    , output        :: Maybe FilePath <?> "optional path to dump statistics"
    , mintettes     :: Maybe Word     <?> "number of mintettes (only for statistics)"
    } deriving (Generic, Show)

instance ParseField  Word
instance ParseField  Severity
instance ParseFields Severity
instance ParseRecord Severity
instance ParseRecord BenchOptions

initializeUsers :: ByteString -> FilePath -> [Word] -> IO [UserAddress]
initializeUsers bankHost benchDir userIds = do
    let initUserAction = userThread bankHost benchDir initializeUser
    logInfo $ sformat ("Initializing " % int % " users…") $ length userIds
    mapM initUserAction userIds

initializeSuperUser :: Word
                    -> ByteString
                    -> FilePath
                    -> [UserAddress]
                    -> IO ()
initializeSuperUser txNum bankHost benchDir userAddresses = do
    -- give money to all users
    let bankId = 0
    logInfo "Initializaing user in bankMode…"
    userThread bankHost benchDir (const $ initializeBank txNum userAddresses) bankId
    logInfo
        "Initialized user in bankMode, finishing period"
    runRealMode bankHost $ finishPeriod bankSecretKey
    threadDelay $ 1 * 10 ^ (6 :: Int)

runTransactions
    :: ByteString
    -> Word
    -> FilePath
    -> [UserAddress]
    -> [Word]
    -> IO ElapsedTime
runTransactions bankHost transactionNum benchDir userAddresses userIds = do
    let benchUserAction =
            userThread bankHost benchDir $
            benchUserTransactions transactionNum userAddresses
    logInfo "Running transactions…"
    measureTime_ $ forConcurrently userIds benchUserAction

dumpStatistics :: Word
               -> Maybe Word
               -> Word
               -> Double
               -> ElapsedTime
               -> FilePath
               -> IO ()
dumpStatistics usersNum mintettesNum txNum tps elapsedTime fp =
    TIO.writeFile fp $
    sformat
        ("rscoin-bench-only-users statistics:\n" % "tps: " % fixed 2 %
         "\nusers: " %
         int %
         "\nmintettes: " %
         stext %
         "\ntransactions per user: " %
         int %
         "\ntransactions total: " %
         int %
         "\nelapsed time: " %
         build %
         "\n")
        tps
        usersNum
        mintettesNumStr
        txNum
        (txNum * usersNum)
        elapsedTime
  where
    mintettesNumStr = maybe "<unknown>" show' mintettesNum

main :: IO ()
main = do
    BenchOptions{..} <- getRecord "rscoin-bench-only-users"
    let userNumber      = fromIntegral $ unHelpful users
        globalSeverity  = fromMaybe Error $ unHelpful severity
        bSeverity       = fromMaybe Info $ unHelpful benchSeverity
        transactionNum  = fromMaybe 1000 $ unHelpful transactions
        bankHost        = unHelpful bank
    withSystemTempDirectory tempBenchDirectory $ \benchDir -> do
        initLogging globalSeverity
        initBenchLogger bSeverity

        let userIds    = [1 .. userNumber]
        userAddresses <- initializeUsers bankHost benchDir userIds
        initializeSuperUser transactionNum bankHost benchDir userAddresses

        t <- runTransactions bankHost transactionNum benchDir userAddresses userIds
        logInfo . sformat ("Elapsed time: " % build) $ t
        let txTotal = transactionNum * userNumber
            tps = perSecond txTotal $ elapsedWallTime t
        logInfo . sformat ("TPS: " % fixed 2) $ tps
        maybe
            (return ())
            (dumpStatistics userNumber (unHelpful mintettes) transactionNum tps t) $
            unHelpful output
