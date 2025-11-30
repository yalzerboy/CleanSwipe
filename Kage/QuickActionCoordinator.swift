//
//  QuickActionCoordinator.swift
//  Kage
//
//  Created by Cursor on 09/11/2025.
//

import Combine
import Foundation

final class QuickActionCoordinator: ObservableObject {
    @Published var pendingAction: QuickActionType?
}

