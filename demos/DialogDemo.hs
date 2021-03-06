{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
{-# LANGUAGE OverloadedStrings #-}
module Main where

import qualified Data.Text as T
import Graphics.Vty hiding (Button)
import Graphics.Vty.Widgets.All

main :: IO ()
main = do
  e <- editWidget
  fg <- newFocusGroup
  addToFocusGroup fg e

  u <- plainText "Enter some text and press enter." <--> return e
       >>= withBoxSpacing 1

  pe <- padded u (padLeftRight 2)
  (d, dFg) <- newDialog pe "<enter text>"
  setNormalAttribute d (white `on` blue)

  c <- centered =<< withPadding (padLeftRight 10) (dialogWidget d)

  -- When the edit widget changes, set the dialog's title.
  e `onChange` setDialogTitle d

  -- When the user presses Enter in the edit widget, accept the
  -- dialog.
  e `onActivate` (const $ acceptDialog d)

  -- Exit either way.
  d `onDialogAccept` const shutdownUi
  d `onDialogCancel` const shutdownUi

  coll <- newCollection
  _ <- addToCollection coll c =<< (mergeFocusGroups fg dFg)

  runUi coll $ defaultContext { focusAttr = black `on` yellow }

  (putStrLn . ("You entered: " ++) . T.unpack) =<< getEditText e