//
//  Item.swift
//  MEDSAI
//
//  Created by Mac on 15/08/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
