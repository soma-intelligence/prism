//
//  SomaTools.swift
//  Prism
//

import Foundation

/// The namespace every tool engine lives in.
///
/// The engines are plain Swift: pure
/// functions over inputs derived from Apple Health, no store, no view. They sit
/// under one name so a type like `CircadianMath` or `SleepCycleModel` cannot
/// collide with a type of the same name another part of the app ports later.
nonisolated enum SomaTools {}
