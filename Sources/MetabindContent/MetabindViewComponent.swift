//
// MetabindViewComponent.swift
//
// © 2025 Yap Studios LLC
//

import SwiftUI

import BindJS

struct MetabindViewComponent: ComponentRepresentable {
    @Environment(\.componentRepresentableContext) var context
    static var name: String = "MetabindView"
    
    var body: some View {
        if let contentId = context?.props["contentId"] as? String {
            MetabindView(contentId: contentId)
        } else {
            context?.content
        }
    }
}
