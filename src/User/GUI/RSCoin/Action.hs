-- | Data type for actions performed by ActionsExecutor.

module GUI.RSCoin.Action (Action (..)) where

import           Data.Int    (Int64)

import           RSCoin.Core (Address)

-- | Actions to be performed by ActionsExecutor.
data Action = Exit
            | Send Address Int64
            | Update
