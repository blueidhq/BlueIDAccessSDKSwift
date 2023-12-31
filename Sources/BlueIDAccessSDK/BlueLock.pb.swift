// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: BlueLock.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

public enum BlueLockState: SwiftProtobuf.Enum {
  public typealias RawValue = Int
  case unknownLockState // = 1
  case locked // = 2
  case unlocked // = 3
  case jammed // = 4

  public init() {
    self = .unknownLockState
  }

  public init?(rawValue: Int) {
    switch rawValue {
    case 1: self = .unknownLockState
    case 2: self = .locked
    case 3: self = .unlocked
    case 4: self = .jammed
    default: return nil
    }
  }

  public var rawValue: Int {
    switch self {
    case .unknownLockState: return 1
    case .locked: return 2
    case .unlocked: return 3
    case .jammed: return 4
    }
  }

}

#if swift(>=4.2)

extension BlueLockState: CaseIterable {
  // Support synthesized by the compiler.
}

#endif  // swift(>=4.2)

public struct BlueLockConfig {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Schedules for when the lock opens automatically
  public var openSchedules: [BlueLocalTimeSchedule] = []

  /// If set to true then the lock opens by schedule only after it was first
  /// opened by an authenticated user and is within any of the open schedules
  public var openScheduleByUser: Bool {
    get {return _openScheduleByUser ?? false}
    set {_openScheduleByUser = newValue}
  }
  /// Returns true if `openScheduleByUser` has been explicitly set.
  public var hasOpenScheduleByUser: Bool {return self._openScheduleByUser != nil}
  /// Clears the value of `openScheduleByUser`. Subsequent reads from it will return its default value.
  public mutating func clearOpenScheduleByUser() {self._openScheduleByUser = nil}

  /// If set keeps the lock closed on federal vacation days
  public var keepClosedOnHolidays: Bool {
    get {return _keepClosedOnHolidays ?? false}
    set {_keepClosedOnHolidays = newValue}
  }
  /// Returns true if `keepClosedOnHolidays` has been explicitly set.
  public var hasKeepClosedOnHolidays: Bool {return self._keepClosedOnHolidays != nil}
  /// Clears the value of `keepClosedOnHolidays`. Subsequent reads from it will return its default value.
  public mutating func clearKeepClosedOnHolidays() {self._keepClosedOnHolidays = nil}

  /// Default time in seconds to keep the lock open
  public var defaultOpenTimeSec: UInt32 {
    get {return _defaultOpenTimeSec ?? 5}
    set {_defaultOpenTimeSec = newValue}
  }
  /// Returns true if `defaultOpenTimeSec` has been explicitly set.
  public var hasDefaultOpenTimeSec: Bool {return self._defaultOpenTimeSec != nil}
  /// Clears the value of `defaultOpenTimeSec`. Subsequent reads from it will return its default value.
  public mutating func clearDefaultOpenTimeSec() {self._defaultOpenTimeSec = nil}

  /// Extended time in seconds to keep the lock open
  public var extendedOpenTimeSec: UInt32 {
    get {return _extendedOpenTimeSec ?? 3600}
    set {_extendedOpenTimeSec = newValue}
  }
  /// Returns true if `extendedOpenTimeSec` has been explicitly set.
  public var hasExtendedOpenTimeSec: Bool {return self._extendedOpenTimeSec != nil}
  /// Clears the value of `extendedOpenTimeSec`. Subsequent reads from it will return its default value.
  public mutating func clearExtendedOpenTimeSec() {self._extendedOpenTimeSec = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _openScheduleByUser: Bool? = nil
  fileprivate var _keepClosedOnHolidays: Bool? = nil
  fileprivate var _defaultOpenTimeSec: UInt32? = nil
  fileprivate var _extendedOpenTimeSec: UInt32? = nil
}

public struct BlueLockStatus {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var state: BlueLockState {
    get {return _state ?? .unknownLockState}
    set {_state = newValue}
  }
  /// Returns true if `state` has been explicitly set.
  public var hasState: Bool {return self._state != nil}
  /// Clears the value of `state`. Subsequent reads from it will return its default value.
  public mutating func clearState() {self._state = nil}

  public var openings: UInt32 {
    get {return _openings ?? 0}
    set {_openings = newValue}
  }
  /// Returns true if `openings` has been explicitly set.
  public var hasOpenings: Bool {return self._openings != nil}
  /// Clears the value of `openings`. Subsequent reads from it will return its default value.
  public mutating func clearOpenings() {self._openings = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _state: BlueLockState? = nil
  fileprivate var _openings: UInt32? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension BlueLockState: @unchecked Sendable {}
extension BlueLockConfig: @unchecked Sendable {}
extension BlueLockStatus: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension BlueLockState: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "UnknownLockState"),
    2: .same(proto: "Locked"),
    3: .same(proto: "Unlocked"),
    4: .same(proto: "Jammed"),
  ]
}

extension BlueLockConfig: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "BlueLockConfig"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "openSchedules"),
    2: .same(proto: "openScheduleByUser"),
    20: .same(proto: "keepClosedOnHolidays"),
    21: .same(proto: "defaultOpenTimeSec"),
    22: .same(proto: "extendedOpenTimeSec"),
  ]

  public var isInitialized: Bool {
    if self._openScheduleByUser == nil {return false}
    if self._keepClosedOnHolidays == nil {return false}
    if self._defaultOpenTimeSec == nil {return false}
    if self._extendedOpenTimeSec == nil {return false}
    if !SwiftProtobuf.Internal.areAllInitialized(self.openSchedules) {return false}
    return true
  }

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.openSchedules) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._openScheduleByUser) }()
      case 20: try { try decoder.decodeSingularBoolField(value: &self._keepClosedOnHolidays) }()
      case 21: try { try decoder.decodeSingularUInt32Field(value: &self._defaultOpenTimeSec) }()
      case 22: try { try decoder.decodeSingularUInt32Field(value: &self._extendedOpenTimeSec) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.openSchedules.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.openSchedules, fieldNumber: 1)
    }
    try { if let v = self._openScheduleByUser {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._keepClosedOnHolidays {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 20)
    } }()
    try { if let v = self._defaultOpenTimeSec {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 21)
    } }()
    try { if let v = self._extendedOpenTimeSec {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 22)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: BlueLockConfig, rhs: BlueLockConfig) -> Bool {
    if lhs.openSchedules != rhs.openSchedules {return false}
    if lhs._openScheduleByUser != rhs._openScheduleByUser {return false}
    if lhs._keepClosedOnHolidays != rhs._keepClosedOnHolidays {return false}
    if lhs._defaultOpenTimeSec != rhs._defaultOpenTimeSec {return false}
    if lhs._extendedOpenTimeSec != rhs._extendedOpenTimeSec {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension BlueLockStatus: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "BlueLockStatus"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "state"),
    2: .same(proto: "openings"),
  ]

  public var isInitialized: Bool {
    if self._state == nil {return false}
    if self._openings == nil {return false}
    return true
  }

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._state) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._openings) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._state {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._openings {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: BlueLockStatus, rhs: BlueLockStatus) -> Bool {
    if lhs._state != rhs._state {return false}
    if lhs._openings != rhs._openings {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
