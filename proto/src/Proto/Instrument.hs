{- This file was auto-generated from instrument.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Instrument (
        Instrument(..), CompileEnd(), CompileStart(), Empty(), Event(),
        Event'Event(..), _Event'Halt, _Event'CompileStart,
        _Event'CompileEnd, _Event'Stats, _Event'Progress, Options(),
        Progress(), RebuildRequest(), Stats(), Stats'MemoryEntry()
    ) where
import qualified Control.DeepSeq
import qualified Data.ProtoLens.Prism
import qualified Prelude
import qualified Data.Int
import qualified Data.Monoid
import qualified Data.Word
import qualified Data.ProtoLens
import qualified Data.ProtoLens.Encoding.Bytes
import qualified Data.ProtoLens.Encoding.Growing
import qualified Data.ProtoLens.Encoding.Parser.Unsafe
import qualified Data.ProtoLens.Encoding.Wire
import qualified Data.ProtoLens.Field
import qualified Data.ProtoLens.Message.Enum
import qualified Data.ProtoLens.Service.Types
import qualified Lens.Family2
import qualified Lens.Family2.Unchecked
import qualified Data.Text
import qualified Data.Map
import qualified Data.ByteString
import qualified Data.ByteString.Char8
import qualified Data.Text.Encoding
import qualified Data.Vector
import qualified Data.Vector.Generic
import qualified Data.Vector.Unboxed
import qualified Text.Read
{- | Fields :
     
         * 'Proto.Instrument_Fields.target' @:: Lens' CompileEnd Data.Text.Text@
         * 'Proto.Instrument_Fields.exitCode' @:: Lens' CompileEnd Data.Int.Int32@
         * 'Proto.Instrument_Fields.stderr' @:: Lens' CompileEnd Data.Text.Text@ -}
data CompileEnd
  = CompileEnd'_constructor {_CompileEnd'target :: !Data.Text.Text,
                             _CompileEnd'exitCode :: !Data.Int.Int32,
                             _CompileEnd'stderr :: !Data.Text.Text,
                             _CompileEnd'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompileEnd where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompileEnd "target" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompileEnd'target (\ x__ y__ -> x__ {_CompileEnd'target = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompileEnd "exitCode" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompileEnd'exitCode
           (\ x__ y__ -> x__ {_CompileEnd'exitCode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompileEnd "stderr" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompileEnd'stderr (\ x__ y__ -> x__ {_CompileEnd'stderr = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompileEnd where
  messageName _ = Data.Text.pack "instrument.CompileEnd"
  packedMessageDescriptor _
    = "\n\
      \\n\
      \CompileEnd\DC2\SYN\n\
      \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget\DC2\ESC\n\
      \\texit_code\CAN\STX \SOH(\ENQR\bexitCode\DC2\SYN\n\
      \\ACKstderr\CAN\ETX \SOH(\tR\ACKstderr"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        target__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "target"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"target")) ::
              Data.ProtoLens.FieldDescriptor CompileEnd
        exitCode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "exit_code"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"exitCode")) ::
              Data.ProtoLens.FieldDescriptor CompileEnd
        stderr__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stderr"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"stderr")) ::
              Data.ProtoLens.FieldDescriptor CompileEnd
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, target__field_descriptor),
           (Data.ProtoLens.Tag 2, exitCode__field_descriptor),
           (Data.ProtoLens.Tag 3, stderr__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompileEnd'_unknownFields
        (\ x__ y__ -> x__ {_CompileEnd'_unknownFields = y__})
  defMessage
    = CompileEnd'_constructor
        {_CompileEnd'target = Data.ProtoLens.fieldDefault,
         _CompileEnd'exitCode = Data.ProtoLens.fieldDefault,
         _CompileEnd'stderr = Data.ProtoLens.fieldDefault,
         _CompileEnd'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompileEnd -> Data.ProtoLens.Encoding.Bytes.Parser CompileEnd
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "target"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"target") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "exit_code"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"exitCode") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "stderr"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"stderr") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CompileEnd"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"target") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"exitCode") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"stderr") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData CompileEnd where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompileEnd'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompileEnd'target x__)
                (Control.DeepSeq.deepseq
                   (_CompileEnd'exitCode x__)
                   (Control.DeepSeq.deepseq (_CompileEnd'stderr x__) ())))
{- | Fields :
     
         * 'Proto.Instrument_Fields.target' @:: Lens' CompileStart Data.Text.Text@
         * 'Proto.Instrument_Fields.canDebug' @:: Lens' CompileStart Prelude.Bool@ -}
data CompileStart
  = CompileStart'_constructor {_CompileStart'target :: !Data.Text.Text,
                               _CompileStart'canDebug :: !Prelude.Bool,
                               _CompileStart'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompileStart where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompileStart "target" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompileStart'target
           (\ x__ y__ -> x__ {_CompileStart'target = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompileStart "canDebug" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompileStart'canDebug
           (\ x__ y__ -> x__ {_CompileStart'canDebug = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompileStart where
  messageName _ = Data.Text.pack "instrument.CompileStart"
  packedMessageDescriptor _
    = "\n\
      \\fCompileStart\DC2\SYN\n\
      \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget\DC2\SUB\n\
      \\bcanDebug\CAN\STX \SOH(\bR\bcanDebug"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        target__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "target"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"target")) ::
              Data.ProtoLens.FieldDescriptor CompileStart
        canDebug__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "canDebug"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"canDebug")) ::
              Data.ProtoLens.FieldDescriptor CompileStart
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, target__field_descriptor),
           (Data.ProtoLens.Tag 2, canDebug__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompileStart'_unknownFields
        (\ x__ y__ -> x__ {_CompileStart'_unknownFields = y__})
  defMessage
    = CompileStart'_constructor
        {_CompileStart'target = Data.ProtoLens.fieldDefault,
         _CompileStart'canDebug = Data.ProtoLens.fieldDefault,
         _CompileStart'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompileStart -> Data.ProtoLens.Encoding.Bytes.Parser CompileStart
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "target"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"target") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "canDebug"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"canDebug") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CompileStart"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"target") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"canDebug") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                            _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData CompileStart where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompileStart'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompileStart'target x__)
                (Control.DeepSeq.deepseq (_CompileStart'canDebug x__) ()))
{- | Fields :
      -}
data Empty
  = Empty'_constructor {_Empty'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Empty where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Message Empty where
  messageName _ = Data.Text.pack "instrument.Empty"
  packedMessageDescriptor _
    = "\n\
      \\ENQEmpty"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag = let in Data.Map.fromList []
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Empty'_unknownFields
        (\ x__ y__ -> x__ {_Empty'_unknownFields = y__})
  defMessage = Empty'_constructor {_Empty'_unknownFields = []}
  parseMessage
    = let
        loop :: Empty -> Data.ProtoLens.Encoding.Bytes.Parser Empty
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Empty"
  buildMessage
    = \ _x
        -> Data.ProtoLens.Encoding.Wire.buildFieldSet
             (Lens.Family2.view Data.ProtoLens.unknownFields _x)
instance Control.DeepSeq.NFData Empty where
  rnf
    = \ x__ -> Control.DeepSeq.deepseq (_Empty'_unknownFields x__) ()
{- | Fields :
     
         * 'Proto.Instrument_Fields.maybe'event' @:: Lens' Event (Prelude.Maybe Event'Event)@
         * 'Proto.Instrument_Fields.maybe'halt' @:: Lens' Event (Prelude.Maybe Empty)@
         * 'Proto.Instrument_Fields.halt' @:: Lens' Event Empty@
         * 'Proto.Instrument_Fields.maybe'compileStart' @:: Lens' Event (Prelude.Maybe CompileStart)@
         * 'Proto.Instrument_Fields.compileStart' @:: Lens' Event CompileStart@
         * 'Proto.Instrument_Fields.maybe'compileEnd' @:: Lens' Event (Prelude.Maybe CompileEnd)@
         * 'Proto.Instrument_Fields.compileEnd' @:: Lens' Event CompileEnd@
         * 'Proto.Instrument_Fields.maybe'stats' @:: Lens' Event (Prelude.Maybe Stats)@
         * 'Proto.Instrument_Fields.stats' @:: Lens' Event Stats@
         * 'Proto.Instrument_Fields.maybe'progress' @:: Lens' Event (Prelude.Maybe Progress)@
         * 'Proto.Instrument_Fields.progress' @:: Lens' Event Progress@ -}
data Event
  = Event'_constructor {_Event'event :: !(Prelude.Maybe Event'Event),
                        _Event'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Event where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data Event'Event
  = Event'Halt !Empty |
    Event'CompileStart !CompileStart |
    Event'CompileEnd !CompileEnd |
    Event'Stats !Stats |
    Event'Progress !Progress
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField Event "maybe'event" (Prelude.Maybe Event'Event) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Event "maybe'halt" (Prelude.Maybe Empty) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Event'Halt x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Event'Halt y__))
instance Data.ProtoLens.Field.HasField Event "halt" Empty where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Event'Halt x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Event'Halt y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Event "maybe'compileStart" (Prelude.Maybe CompileStart) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Event'CompileStart x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Event'CompileStart y__))
instance Data.ProtoLens.Field.HasField Event "compileStart" CompileStart where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Event'CompileStart x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Event'CompileStart y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Event "maybe'compileEnd" (Prelude.Maybe CompileEnd) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Event'CompileEnd x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Event'CompileEnd y__))
instance Data.ProtoLens.Field.HasField Event "compileEnd" CompileEnd where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Event'CompileEnd x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Event'CompileEnd y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Event "maybe'stats" (Prelude.Maybe Stats) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Event'Stats x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Event'Stats y__))
instance Data.ProtoLens.Field.HasField Event "stats" Stats where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Event'Stats x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Event'Stats y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Event "maybe'progress" (Prelude.Maybe Progress) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Event'Progress x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Event'Progress y__))
instance Data.ProtoLens.Field.HasField Event "progress" Progress where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Event'event (\ x__ y__ -> x__ {_Event'event = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Event'Progress x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Event'Progress y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message Event where
  messageName _ = Data.Text.pack "instrument.Event"
  packedMessageDescriptor _
    = "\n\
      \\ENQEvent\DC2'\n\
      \\EOThalt\CAN\SOH \SOH(\v2\DC1.instrument.EmptyH\NULR\EOThalt\DC2>\n\
      \\fcompileStart\CAN\STX \SOH(\v2\CAN.instrument.CompileStartH\NULR\fcompileStart\DC28\n\
      \\n\
      \compileEnd\CAN\ETX \SOH(\v2\SYN.instrument.CompileEndH\NULR\n\
      \compileEnd\DC2)\n\
      \\ENQstats\CAN\EOT \SOH(\v2\DC1.instrument.StatsH\NULR\ENQstats\DC22\n\
      \\bprogress\CAN\ENQ \SOH(\v2\DC4.instrument.ProgressH\NULR\bprogressB\a\n\
      \\ENQevent"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        halt__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "halt"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Empty)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'halt")) ::
              Data.ProtoLens.FieldDescriptor Event
        compileStart__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "compileStart"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CompileStart)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'compileStart")) ::
              Data.ProtoLens.FieldDescriptor Event
        compileEnd__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "compileEnd"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CompileEnd)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'compileEnd")) ::
              Data.ProtoLens.FieldDescriptor Event
        stats__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stats"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Stats)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'stats")) ::
              Data.ProtoLens.FieldDescriptor Event
        progress__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "progress"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Progress)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'progress")) ::
              Data.ProtoLens.FieldDescriptor Event
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, halt__field_descriptor),
           (Data.ProtoLens.Tag 2, compileStart__field_descriptor),
           (Data.ProtoLens.Tag 3, compileEnd__field_descriptor),
           (Data.ProtoLens.Tag 4, stats__field_descriptor),
           (Data.ProtoLens.Tag 5, progress__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Event'_unknownFields
        (\ x__ y__ -> x__ {_Event'_unknownFields = y__})
  defMessage
    = Event'_constructor
        {_Event'event = Prelude.Nothing, _Event'_unknownFields = []}
  parseMessage
    = let
        loop :: Event -> Data.ProtoLens.Encoding.Bytes.Parser Event
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "halt"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"halt") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "compileStart"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"compileStart") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "compileEnd"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"compileEnd") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "stats"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"stats") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "progress"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"progress") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Event"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'event") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (Event'Halt v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Event'CompileStart v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Event'CompileEnd v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Event'Stats v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Event'Progress v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData Event where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Event'_unknownFields x__)
             (Control.DeepSeq.deepseq (_Event'event x__) ())
instance Control.DeepSeq.NFData Event'Event where
  rnf (Event'Halt x__) = Control.DeepSeq.rnf x__
  rnf (Event'CompileStart x__) = Control.DeepSeq.rnf x__
  rnf (Event'CompileEnd x__) = Control.DeepSeq.rnf x__
  rnf (Event'Stats x__) = Control.DeepSeq.rnf x__
  rnf (Event'Progress x__) = Control.DeepSeq.rnf x__
_Event'Halt :: Data.ProtoLens.Prism.Prism' Event'Event Empty
_Event'Halt
  = Data.ProtoLens.Prism.prism'
      Event'Halt
      (\ p__
         -> case p__ of
              (Event'Halt p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Event'CompileStart ::
  Data.ProtoLens.Prism.Prism' Event'Event CompileStart
_Event'CompileStart
  = Data.ProtoLens.Prism.prism'
      Event'CompileStart
      (\ p__
         -> case p__ of
              (Event'CompileStart p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Event'CompileEnd ::
  Data.ProtoLens.Prism.Prism' Event'Event CompileEnd
_Event'CompileEnd
  = Data.ProtoLens.Prism.prism'
      Event'CompileEnd
      (\ p__
         -> case p__ of
              (Event'CompileEnd p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Event'Stats :: Data.ProtoLens.Prism.Prism' Event'Event Stats
_Event'Stats
  = Data.ProtoLens.Prism.prism'
      Event'Stats
      (\ p__
         -> case p__ of
              (Event'Stats p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Event'Progress :: Data.ProtoLens.Prism.Prism' Event'Event Progress
_Event'Progress
  = Data.ProtoLens.Prism.prism'
      Event'Progress
      (\ p__
         -> case p__ of
              (Event'Progress p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Instrument_Fields.extraGhcOptions' @:: Lens' Options Data.Text.Text@ -}
data Options
  = Options'_constructor {_Options'extraGhcOptions :: !Data.Text.Text,
                          _Options'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Options where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Options "extraGhcOptions" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Options'extraGhcOptions
           (\ x__ y__ -> x__ {_Options'extraGhcOptions = y__}))
        Prelude.id
instance Data.ProtoLens.Message Options where
  messageName _ = Data.Text.pack "instrument.Options"
  packedMessageDescriptor _
    = "\n\
      \\aOptions\DC2*\n\
      \\DC1extra_ghc_options\CAN\SOH \SOH(\tR\SIextraGhcOptions"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        extraGhcOptions__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "extra_ghc_options"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"extraGhcOptions")) ::
              Data.ProtoLens.FieldDescriptor Options
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, extraGhcOptions__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Options'_unknownFields
        (\ x__ y__ -> x__ {_Options'_unknownFields = y__})
  defMessage
    = Options'_constructor
        {_Options'extraGhcOptions = Data.ProtoLens.fieldDefault,
         _Options'_unknownFields = []}
  parseMessage
    = let
        loop :: Options -> Data.ProtoLens.Encoding.Bytes.Parser Options
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "extra_ghc_options"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"extraGhcOptions") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Options"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"extraGhcOptions") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData Options where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Options'_unknownFields x__)
             (Control.DeepSeq.deepseq (_Options'extraGhcOptions x__) ())
{- | Fields :
     
         * 'Proto.Instrument_Fields.target' @:: Lens' Progress Data.Text.Text@
         * 'Proto.Instrument_Fields.progressMessage' @:: Lens' Progress Data.Text.Text@
         * 'Proto.Instrument_Fields.progressInfo' @:: Lens' Progress Data.Text.Text@ -}
data Progress
  = Progress'_constructor {_Progress'target :: !Data.Text.Text,
                           _Progress'progressMessage :: !Data.Text.Text,
                           _Progress'progressInfo :: !Data.Text.Text,
                           _Progress'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Progress where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Progress "target" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Progress'target (\ x__ y__ -> x__ {_Progress'target = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Progress "progressMessage" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Progress'progressMessage
           (\ x__ y__ -> x__ {_Progress'progressMessage = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Progress "progressInfo" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Progress'progressInfo
           (\ x__ y__ -> x__ {_Progress'progressInfo = y__}))
        Prelude.id
instance Data.ProtoLens.Message Progress where
  messageName _ = Data.Text.pack "instrument.Progress"
  packedMessageDescriptor _
    = "\n\
      \\bProgress\DC2\SYN\n\
      \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget\DC2(\n\
      \\SIprogressMessage\CAN\STX \SOH(\tR\SIprogressMessage\DC2\"\n\
      \\fprogressInfo\CAN\ETX \SOH(\tR\fprogressInfo"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        target__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "target"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"target")) ::
              Data.ProtoLens.FieldDescriptor Progress
        progressMessage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "progressMessage"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"progressMessage")) ::
              Data.ProtoLens.FieldDescriptor Progress
        progressInfo__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "progressInfo"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"progressInfo")) ::
              Data.ProtoLens.FieldDescriptor Progress
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, target__field_descriptor),
           (Data.ProtoLens.Tag 2, progressMessage__field_descriptor),
           (Data.ProtoLens.Tag 3, progressInfo__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Progress'_unknownFields
        (\ x__ y__ -> x__ {_Progress'_unknownFields = y__})
  defMessage
    = Progress'_constructor
        {_Progress'target = Data.ProtoLens.fieldDefault,
         _Progress'progressMessage = Data.ProtoLens.fieldDefault,
         _Progress'progressInfo = Data.ProtoLens.fieldDefault,
         _Progress'_unknownFields = []}
  parseMessage
    = let
        loop :: Progress -> Data.ProtoLens.Encoding.Bytes.Parser Progress
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "target"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"target") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "progressMessage"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"progressMessage") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "progressInfo"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"progressInfo") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Progress"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"target") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"progressMessage") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"progressInfo") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData Progress where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Progress'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_Progress'target x__)
                (Control.DeepSeq.deepseq
                   (_Progress'progressMessage x__)
                   (Control.DeepSeq.deepseq (_Progress'progressInfo x__) ())))
{- | Fields :
     
         * 'Proto.Instrument_Fields.target' @:: Lens' RebuildRequest Data.Text.Text@ -}
data RebuildRequest
  = RebuildRequest'_constructor {_RebuildRequest'target :: !Data.Text.Text,
                                 _RebuildRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RebuildRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RebuildRequest "target" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RebuildRequest'target
           (\ x__ y__ -> x__ {_RebuildRequest'target = y__}))
        Prelude.id
instance Data.ProtoLens.Message RebuildRequest where
  messageName _ = Data.Text.pack "instrument.RebuildRequest"
  packedMessageDescriptor _
    = "\n\
      \\SORebuildRequest\DC2\SYN\n\
      \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        target__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "target"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"target")) ::
              Data.ProtoLens.FieldDescriptor RebuildRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, target__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RebuildRequest'_unknownFields
        (\ x__ y__ -> x__ {_RebuildRequest'_unknownFields = y__})
  defMessage
    = RebuildRequest'_constructor
        {_RebuildRequest'target = Data.ProtoLens.fieldDefault,
         _RebuildRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RebuildRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser RebuildRequest
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "target"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"target") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "RebuildRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"target") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData RebuildRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RebuildRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq (_RebuildRequest'target x__) ())
{- | Fields :
     
         * 'Proto.Instrument_Fields.memory' @:: Lens' Stats (Data.Map.Map Data.Text.Text Data.Int.Int64)@
         * 'Proto.Instrument_Fields.gcCpuNs' @:: Lens' Stats Data.Int.Int64@
         * 'Proto.Instrument_Fields.cpuNs' @:: Lens' Stats Data.Int.Int64@ -}
data Stats
  = Stats'_constructor {_Stats'memory :: !(Data.Map.Map Data.Text.Text Data.Int.Int64),
                        _Stats'gcCpuNs :: !Data.Int.Int64,
                        _Stats'cpuNs :: !Data.Int.Int64,
                        _Stats'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Stats where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Stats "memory" (Data.Map.Map Data.Text.Text Data.Int.Int64) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Stats'memory (\ x__ y__ -> x__ {_Stats'memory = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Stats "gcCpuNs" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Stats'gcCpuNs (\ x__ y__ -> x__ {_Stats'gcCpuNs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Stats "cpuNs" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Stats'cpuNs (\ x__ y__ -> x__ {_Stats'cpuNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message Stats where
  messageName _ = Data.Text.pack "instrument.Stats"
  packedMessageDescriptor _
    = "\n\
      \\ENQStats\DC25\n\
      \\ACKmemory\CAN\SOH \ETX(\v2\GS.instrument.Stats.MemoryEntryR\ACKmemory\DC2\SUB\n\
      \\tgc_cpu_ns\CAN\STX \SOH(\ETXR\agcCpuNs\DC2\NAK\n\
      \\ACKcpu_ns\CAN\ETX \SOH(\ETXR\ENQcpuNs\SUB9\n\
      \\vMemoryEntry\DC2\DLE\n\
      \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\DC4\n\
      \\ENQvalue\CAN\STX \SOH(\ETXR\ENQvalue:\STX8\SOH"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        memory__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "memory"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Stats'MemoryEntry)
              (Data.ProtoLens.MapField
                 (Data.ProtoLens.Field.field @"key")
                 (Data.ProtoLens.Field.field @"value")
                 (Data.ProtoLens.Field.field @"memory")) ::
              Data.ProtoLens.FieldDescriptor Stats
        gcCpuNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "gc_cpu_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"gcCpuNs")) ::
              Data.ProtoLens.FieldDescriptor Stats
        cpuNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cpu_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"cpuNs")) ::
              Data.ProtoLens.FieldDescriptor Stats
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, memory__field_descriptor),
           (Data.ProtoLens.Tag 2, gcCpuNs__field_descriptor),
           (Data.ProtoLens.Tag 3, cpuNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Stats'_unknownFields
        (\ x__ y__ -> x__ {_Stats'_unknownFields = y__})
  defMessage
    = Stats'_constructor
        {_Stats'memory = Data.Map.empty,
         _Stats'gcCpuNs = Data.ProtoLens.fieldDefault,
         _Stats'cpuNs = Data.ProtoLens.fieldDefault,
         _Stats'_unknownFields = []}
  parseMessage
    = let
        loop :: Stats -> Data.ProtoLens.Encoding.Bytes.Parser Stats
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !(entry :: Stats'MemoryEntry) <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                   (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                                                       Data.ProtoLens.Encoding.Bytes.isolate
                                                                         (Prelude.fromIntegral len)
                                                                         Data.ProtoLens.parseMessage)
                                                                   "memory"
                                (let
                                   key = Lens.Family2.view (Data.ProtoLens.Field.field @"key") entry
                                   value
                                     = Lens.Family2.view (Data.ProtoLens.Field.field @"value") entry
                                 in
                                   loop
                                     (Lens.Family2.over
                                        (Data.ProtoLens.Field.field @"memory")
                                        (\ !t -> Data.Map.insert key value t) x))
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "gc_cpu_ns"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"gcCpuNs") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "cpu_ns"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"cpuNs") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Stats"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.Monoid.mconcat
                (Prelude.map
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.ProtoLens.encodeMessage
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"key") (Prelude.fst _v)
                                 (Lens.Family2.set
                                    (Data.ProtoLens.Field.field @"value") (Prelude.snd _v)
                                    (Data.ProtoLens.defMessage :: Stats'MemoryEntry)))))
                   (Data.Map.toList
                      (Lens.Family2.view (Data.ProtoLens.Field.field @"memory") _x))))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"gcCpuNs") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"cpuNs") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData Stats where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Stats'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_Stats'memory x__)
                (Control.DeepSeq.deepseq
                   (_Stats'gcCpuNs x__)
                   (Control.DeepSeq.deepseq (_Stats'cpuNs x__) ())))
{- | Fields :
     
         * 'Proto.Instrument_Fields.key' @:: Lens' Stats'MemoryEntry Data.Text.Text@
         * 'Proto.Instrument_Fields.value' @:: Lens' Stats'MemoryEntry Data.Int.Int64@ -}
data Stats'MemoryEntry
  = Stats'MemoryEntry'_constructor {_Stats'MemoryEntry'key :: !Data.Text.Text,
                                    _Stats'MemoryEntry'value :: !Data.Int.Int64,
                                    _Stats'MemoryEntry'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Stats'MemoryEntry where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Stats'MemoryEntry "key" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Stats'MemoryEntry'key
           (\ x__ y__ -> x__ {_Stats'MemoryEntry'key = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Stats'MemoryEntry "value" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Stats'MemoryEntry'value
           (\ x__ y__ -> x__ {_Stats'MemoryEntry'value = y__}))
        Prelude.id
instance Data.ProtoLens.Message Stats'MemoryEntry where
  messageName _ = Data.Text.pack "instrument.Stats.MemoryEntry"
  packedMessageDescriptor _
    = "\n\
      \\vMemoryEntry\DC2\DLE\n\
      \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\DC4\n\
      \\ENQvalue\CAN\STX \SOH(\ETXR\ENQvalue:\STX8\SOH"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        key__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"key")) ::
              Data.ProtoLens.FieldDescriptor Stats'MemoryEntry
        value__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "value"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"value")) ::
              Data.ProtoLens.FieldDescriptor Stats'MemoryEntry
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, key__field_descriptor),
           (Data.ProtoLens.Tag 2, value__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Stats'MemoryEntry'_unknownFields
        (\ x__ y__ -> x__ {_Stats'MemoryEntry'_unknownFields = y__})
  defMessage
    = Stats'MemoryEntry'_constructor
        {_Stats'MemoryEntry'key = Data.ProtoLens.fieldDefault,
         _Stats'MemoryEntry'value = Data.ProtoLens.fieldDefault,
         _Stats'MemoryEntry'_unknownFields = []}
  parseMessage
    = let
        loop ::
          Stats'MemoryEntry
          -> Data.ProtoLens.Encoding.Bytes.Parser Stats'MemoryEntry
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "key"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"key") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "value"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"value") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "MemoryEntry"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"key") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"value") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData Stats'MemoryEntry where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Stats'MemoryEntry'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_Stats'MemoryEntry'key x__)
                (Control.DeepSeq.deepseq (_Stats'MemoryEntry'value x__) ()))
data Instrument = Instrument {}
instance Data.ProtoLens.Service.Types.Service Instrument where
  type ServiceName Instrument = "Instrument"
  type ServicePackage Instrument = "instrument"
  type ServiceMethods Instrument = '["notifyMe",
                                     "setOptions",
                                     "triggerRebuild"]
  packedServiceDescriptor _
    = "\n\
      \\n\
      \Instrument\DC24\n\
      \\bNotifyMe\DC2\DC1.instrument.Empty\SUB\DC1.instrument.Event\"\NUL0\SOH\DC26\n\
      \\n\
      \SetOptions\DC2\DC3.instrument.Options\SUB\DC1.instrument.Empty\"\NUL\DC2A\n\
      \\SOTriggerRebuild\DC2\SUB.instrument.RebuildRequest\SUB\DC1.instrument.Empty\"\NUL"
instance Data.ProtoLens.Service.Types.HasMethodImpl Instrument "notifyMe" where
  type MethodName Instrument "notifyMe" = "NotifyMe"
  type MethodInput Instrument "notifyMe" = Empty
  type MethodOutput Instrument "notifyMe" = Event
  type MethodStreamingType Instrument "notifyMe" = 'Data.ProtoLens.Service.Types.ServerStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Instrument "setOptions" where
  type MethodName Instrument "setOptions" = "SetOptions"
  type MethodInput Instrument "setOptions" = Options
  type MethodOutput Instrument "setOptions" = Empty
  type MethodStreamingType Instrument "setOptions" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Instrument "triggerRebuild" where
  type MethodName Instrument "triggerRebuild" = "TriggerRebuild"
  type MethodInput Instrument "triggerRebuild" = RebuildRequest
  type MethodOutput Instrument "triggerRebuild" = Empty
  type MethodStreamingType Instrument "triggerRebuild" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\DLEinstrument.proto\DC2\n\
    \instrument\"\a\n\
    \\ENQEmpty\"B\n\
    \\fCompileStart\DC2\SYN\n\
    \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget\DC2\SUB\n\
    \\bcanDebug\CAN\STX \SOH(\bR\bcanDebug\"Y\n\
    \\n\
    \CompileEnd\DC2\SYN\n\
    \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget\DC2\ESC\n\
    \\texit_code\CAN\STX \SOH(\ENQR\bexitCode\DC2\SYN\n\
    \\ACKstderr\CAN\ETX \SOH(\tR\ACKstderr\"p\n\
    \\bProgress\DC2\SYN\n\
    \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget\DC2(\n\
    \\SIprogressMessage\CAN\STX \SOH(\tR\SIprogressMessage\DC2\"\n\
    \\fprogressInfo\CAN\ETX \SOH(\tR\fprogressInfo\"\172\SOH\n\
    \\ENQStats\DC25\n\
    \\ACKmemory\CAN\SOH \ETX(\v2\GS.instrument.Stats.MemoryEntryR\ACKmemory\DC2\SUB\n\
    \\tgc_cpu_ns\CAN\STX \SOH(\ETXR\agcCpuNs\DC2\NAK\n\
    \\ACKcpu_ns\CAN\ETX \SOH(\ETXR\ENQcpuNs\SUB9\n\
    \\vMemoryEntry\DC2\DLE\n\
    \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\DC4\n\
    \\ENQvalue\CAN\STX \SOH(\ETXR\ENQvalue:\STX8\SOH\"\146\STX\n\
    \\ENQEvent\DC2'\n\
    \\EOThalt\CAN\SOH \SOH(\v2\DC1.instrument.EmptyH\NULR\EOThalt\DC2>\n\
    \\fcompileStart\CAN\STX \SOH(\v2\CAN.instrument.CompileStartH\NULR\fcompileStart\DC28\n\
    \\n\
    \compileEnd\CAN\ETX \SOH(\v2\SYN.instrument.CompileEndH\NULR\n\
    \compileEnd\DC2)\n\
    \\ENQstats\CAN\EOT \SOH(\v2\DC1.instrument.StatsH\NULR\ENQstats\DC22\n\
    \\bprogress\CAN\ENQ \SOH(\v2\DC4.instrument.ProgressH\NULR\bprogressB\a\n\
    \\ENQevent\"5\n\
    \\aOptions\DC2*\n\
    \\DC1extra_ghc_options\CAN\SOH \SOH(\tR\SIextraGhcOptions\"(\n\
    \\SORebuildRequest\DC2\SYN\n\
    \\ACKtarget\CAN\SOH \SOH(\tR\ACKtarget2\189\SOH\n\
    \\n\
    \Instrument\DC24\n\
    \\bNotifyMe\DC2\DC1.instrument.Empty\SUB\DC1.instrument.Event\"\NUL0\SOH\DC26\n\
    \\n\
    \SetOptions\DC2\DC3.instrument.Options\SUB\DC1.instrument.Empty\"\NUL\DC2A\n\
    \\SOTriggerRebuild\DC2\SUB.instrument.RebuildRequest\SUB\DC1.instrument.Empty\"\NULJ\160\v\n\
    \\ACK\DC2\EOT\NUL\NUL3\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DC3\n\
    \\t\n\
    \\STX\EOT\NUL\DC2\ETX\EOT\NUL\DLE\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\EOT\b\r\n\
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\ACK\NUL\t\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\ACK\b\DC4\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\a\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\a\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\a\t\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\a\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX\b\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX\b\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX\b\a\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX\b\DC2\DC3\n\
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT\v\NUL\SI\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\v\b\DC2\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\f\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\f\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\f\t\SI\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\f\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\r\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\r\STX\a\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\r\b\DC1\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\r\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\SO\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\SO\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\SO\t\SI\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\SO\DC2\DC3\n\
    \\n\
    \\n\
    \\STX\EOT\ETX\DC2\EOT\DC1\NUL\NAK\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX\DC1\b\DLE\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX\DC2\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX\DC2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX\DC2\t\SI\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX\DC2\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX\DC3\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX\DC3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX\DC3\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX\DC3\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX\DC4\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX\DC4\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX\DC4\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX\DC4\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\EOT\DC2\EOT\ETB\NUL\ESC\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX\ETB\b\r\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX\CAN\STX \n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ACK\DC2\ETX\CAN\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX\CAN\NAK\ESC\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX\CAN\RS\US\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX\EM\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX\EM\STX\a\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX\EM\b\DC1\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX\EM\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\STX\DC2\ETX\SUB\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ENQ\DC2\ETX\SUB\STX\a\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\ETX\SUB\b\SO\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\ETX\SUB\DC1\DC2\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOT\GS\NUL%\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETX\GS\b\r\n\
    \\f\n\
    \\EOT\EOT\ENQ\b\NUL\DC2\EOT\RS\STX$\ETX\n\
    \\f\n\
    \\ENQ\EOT\ENQ\b\NUL\SOH\DC2\ETX\RS\b\r\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETX\US\EOT\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ACK\DC2\ETX\US\EOT\t\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETX\US\n\
    \\SO\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETX\US\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETX \EOT\"\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ACK\DC2\ETX \EOT\DLE\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETX \DC1\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETX  !\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETX!\EOT\RS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ACK\DC2\ETX!\EOT\SO\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETX!\SI\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETX!\FS\GS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\ETX\"\EOT\DC4\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ACK\DC2\ETX\"\EOT\t\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\ETX\"\n\
    \\SI\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\ETX\"\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\EOT\DC2\ETX#\EOT\SUB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ACK\DC2\ETX#\EOT\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\SOH\DC2\ETX#\r\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ETX\DC2\ETX#\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\ACK\DC2\EOT'\NUL)\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX'\b\SI\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETX(\STX\US\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ENQ\DC2\ETX(\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETX(\t\SUB\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETX(\GS\RS\n\
    \\n\
    \\n\
    \\STX\EOT\a\DC2\EOT+\NUL-\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\a\SOH\DC2\ETX+\b\SYN\n\
    \\v\n\
    \\EOT\EOT\a\STX\NUL\DC2\ETX,\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ENQ\DC2\ETX,\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\ETX,\t\SI\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\ETX,\DC2\DC3\n\
    \\n\
    \\n\
    \\STX\ACK\NUL\DC2\EOT/\NUL3\SOH\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX/\b\DC2\n\
    \\v\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX0\STX/\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX0\ACK\SO\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX0\SI\DC4\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ACK\DC2\ETX0\US%\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX0&+\n\
    \\v\n\
    \\EOT\ACK\NUL\STX\SOH\DC2\ETX1\STX,\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\SOH\DC2\ETX1\ACK\DLE\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\STX\DC2\ETX1\DC1\CAN\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\ETX\DC2\ETX1#(\n\
    \\v\n\
    \\EOT\ACK\NUL\STX\STX\DC2\ETX2\STX7\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\STX\SOH\DC2\ETX2\ACK\DC4\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\STX\STX\DC2\ETX2\NAK#\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\STX\ETX\DC2\ETX2.3b\ACKproto3"