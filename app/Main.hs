{-# LANGUAGE ScopedTypeVariables #-}
-- | Program runner.

module Main where

import           Control.Exception
import           Control.Monad
import qualified Data.Map.Strict as M
import           Data.Yaml (decodeFileThrow)
import           Options.Applicative
import           System.Directory
import           System.IO
import           System.Posix.Signals
import           System.Posix.Types
import           System.Process
import           Text.Read

data Config = Config
  { configProgram :: FilePath
  , configPid :: FilePath
  , configLog :: FilePath
  , configStderr :: FilePath
  , configStdout :: FilePath
  , configEnv :: [(String, String)]
  , configEnvFile :: Maybe FilePath
  , configPwd :: FilePath
  , configArgs :: [String]
  , configLogEnv :: Bool
  , configTerm :: Bool
  } deriving (Show)

sample :: Parser Config
sample =
  Config <$>
  strArgument (metavar "PROGRAM" <> help "Run this program") <*>
  strOption
    (long "pid" <> metavar "FILEPATH" <>
     help "Write the process ID to this file" <> value "cron-daemon-pid") <*>
  strOption (long "log" <> metavar "FILEPATH" <> help "Log file" <> value "/dev/stdout") <*>
  strOption (long "stderr" <> metavar "FILEPATH" <> help "Process stderr file" <> value "/dev/stderr") <*>
  strOption (long "stdout" <> metavar "FILEPATH" <> help "Process stdout file" <> value "/dev/stdout") <*>
  many
    (option
       (maybeReader (parseEnv))
       (long "env" <> short 'e' <> metavar "NAME=value" <>
        help "Environment variable")) <*>
  optional (strOption (long "env-file" <> metavar "FILEPATH" <> help "YAML file containing an object of environment variables")) <*>
  strOption (long "pwd" <> metavar "DIR" <> help "Working directory" <> value ".") <*>
  many
    (strArgument (metavar "ARGUMENT" <> help "Argument for the child process")) <*>
  flag
    False
    True
    (help "Log environment variables in log file (default: false)" <>
     long "debug-log-env") <*>
  flag
    False
    True
    (help "Terminate the process if it's already running (can be used for restart/update of binary)" <>
     long "terminate")

parseEnv :: String -> Maybe (String, String)
parseEnv =
  \s ->
    case break (== '=') s of
      (name, val)
        | not (null val) && not (null name) -> Just (name, drop 1 val)
        | otherwise -> Nothing

main :: IO ()
main = do
  config <- execParser opts
  start config
  where
    opts =
      info
        (sample <**> helper)
        (fullDesc <> progDesc "Run a program as a daemon with cron" <>
         header "cron-daemon - Run a program as a daemon with cron")

start :: Config -> IO ()
start config = do
  pidFileExists <- doesFileExist (configPid config)
  if pidFileExists
    then do
      pidbytes <- readFile (configPid config)
      case readMaybe pidbytes of
        Just u32 -> do
          catch
            (do signalProcess 0 (CPid u32)
                when
                  (configTerm config)
                  (do logInfo
                        "Terminating the process as requested and re-launching."
                      signalProcess sigTERM (CPid u32)
                      launch))
            (\(_ :: SomeException) -> do
               logInfo ("Process ID " ++ show u32 ++ " not running.")
               launch)
        Nothing -> logError "Failed to read process ID as a 32-bit integer!"
    else do
      logInfo ("PID file does not exist: " ++ configPid config)
      launch
  where
    logInfo line = appendFile (configLog config) ("INFO: " ++ line ++ "\n")
    logError line = appendFile (configLog config) ("ERROR: " ++ line ++ "\n")
    launch = do
      envFromFile <-
        case configEnvFile config of
          Nothing -> pure mempty
          Just fp -> fmap M.toList (decodeFileThrow fp)
      logInfo ("Launching " ++ configProgram config)
      logInfo ("Arguments: " ++ show (configArgs config))
      when
        (configLogEnv config)
        (logInfo ("Environment: " ++ show (configEnv config)))
      errfile <- openFile (configStderr config) AppendMode
      outfile <- openFile (configStdout config) AppendMode
      (_, _, _, ph) <-
        catch
          (createProcess
             (proc (configProgram config) (configArgs config))
               { env = Just (configEnv config <> envFromFile)
               , std_in = NoStream
               , std_out = UseHandle outfile
               , std_err = UseHandle errfile
               , cwd = Just (configPwd config)
               })
          (\(e :: SomeException) ->
             logError "Failed to launch process." >> throw e)
      mpid <- getPid ph
      case mpid of
        Just (CPid pid) -> do
          writeFile (configPid config) (show pid)
          logInfo ("Successfully launched PID: " ++ show pid)
        Nothing -> logError "Failed to get process ID!"
