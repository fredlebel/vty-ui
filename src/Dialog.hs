{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Main where

import Data.IORef
import Control.Monad
import Control.Monad.Trans
import System.Exit
import Graphics.Vty hiding (Button)
import Graphics.Vty.Widgets.All

data Button = Button { buttonText :: String
                     , buttonWidget :: Widget Padded
                     }

onButtonPressed :: (MonadIO m) => Button -> IO () -> m ()
onButtonPressed b act = do
  (buttonWidget b) `onKeyPressed` \_ k _ ->
      do
        case k of
          KEnter -> act
          _ -> return ()
        return False

button :: (MonadIO m) => String -> m Button
button msg = do
  w <- simpleText msg >>=
       withPadding (padLeftRight 3) >>=
       withNormalAttribute (white `on` black) >>=
       withFocusAttribute (blue `on` white)

  return $ Button msg w

data EventHandlers w e = EventHandlers { registeredHandlers :: [(e, IO ())]
                                       -- ^Specific event handlers.
                                       -- Might want an "any" event handler list, too.
                                       }

addEventHandler :: w -> e -> IO () -> EventHandlers w e -> EventHandlers w e
addEventHandler w e act eh =
    eh { registeredHandlers = registeredHandlers eh ++ [(e, act)] }

data DialogEvent = DialogAccept
                 | DialogCancel
                   deriving (Eq)

class (Eq e) => EventSource w e where
    getEventHandlers :: w -> IORef (EventHandlers w e)

    onEvent :: (MonadIO m) => e -> w -> IO () -> m ()
    onEvent ev w act =
        liftIO $ modifyIORef (getEventHandlers w) $ addEventHandler w ev act

    dispatchEvent :: (MonadIO m) => w -> e -> m ()
    dispatchEvent w ev = do
        let eRef = getEventHandlers w
        eh <- liftIO $ readIORef eRef
        forM_ (registeredHandlers eh) $ \(e', act) ->
            if e' == ev then liftIO act else return ()

instance EventSource Dialog DialogEvent where
    getEventHandlers = dialogHandlers

data Dialog = Dialog { okButton :: Button
                     , cancelButton :: Button
                     , dialogWidget :: Widget (VCentered (HCentered Padded))
                     , setDialogTitle :: String -> IO ()
                     , dialogHandlers :: IORef (EventHandlers Dialog DialogEvent)
                     }

dialog :: (MonadIO m, Show a) => Widget a -> String -> Maybe (Widget FocusGroup)
       -> m Dialog
dialog body title mFg = do
  okB <- button "OK"
  cancelB <- button "Cancel"

  buttonBox <- (return $ buttonWidget okB) <++> (return $ buttonWidget cancelB)
  setBoxSpacing buttonBox 4

  b <- (hCentered body) <--> (hCentered buttonBox) >>= withBoxSpacing 1
  b2 <- padded b (padTopBottom 1)

  fg <- case mFg of
          Just g -> return g
          Nothing -> newFocusGroup

  addToFocusGroup fg $ buttonWidget okB
  addToFocusGroup fg $ buttonWidget cancelB

  b <- bordered b2 >>=
       withBorderedLabel title >>=
       withNormalAttribute (white `on` blue)

  c <- centered =<< withPadding (padLeftRight 10) b

  setFocusGroup c fg
  eRef <- liftIO $ newIORef $ EventHandlers []

  let dlg = Dialog { okButton = okB
                   , cancelButton = cancelB
                   , dialogWidget = c
                   , setDialogTitle = setBorderedLabel b
                   , dialogHandlers = eRef
                   }

  okB `onButtonPressed` dispatchEvent dlg DialogAccept
  cancelB `onButtonPressed` dispatchEvent dlg DialogCancel

  return dlg

onDialogAccept :: (MonadIO m) => Dialog -> IO () -> m ()
onDialogAccept = onEvent DialogAccept

onDialogCancel :: (MonadIO m) => Dialog -> IO () -> m ()
onDialogCancel = onEvent DialogCancel

main :: IO ()
main = do
  e <- editWidget
  fg <- newFocusGroup
  addToFocusGroup fg e

  u <- (simpleText "Enter some text and press enter.") <--> (return e) >>= withBoxSpacing 1

  pe <- padded u (padLeftRight 2)
  d <- dialog pe "<enter text>" (Just fg)

  let updateTitle = setDialogTitle d =<< getEditText e

  e `onChange` \_ _ -> updateTitle

  d `onDialogAccept` exitSuccess
  d `onDialogCancel` exitSuccess

  fg `onKeyPressed` \_ k _ ->
      case k of
        KASCII 'q' -> exitSuccess
        KEsc -> exitSuccess
        _ -> return False

  runUi (dialogWidget d) $ defaultContext { focusAttr = black `on` yellow }
