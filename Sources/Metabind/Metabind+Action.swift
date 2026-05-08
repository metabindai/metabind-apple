//
// Metabind+Action.swift
//
// © 2025 Yap Studios LLC
//

import SwiftUI
import BindJS

public struct MetabindContentAction {
    public let name: String
    public let props: [String: Any]
}

public extension View {
    func onMetabindAction(_ body: @escaping (MetabindContentAction) -> Void) -> some View {
        modifier(OnMetabindActionModifier(body: body))
    }
}

private struct OnMetabindActionModifier: ViewModifier {
    let body: (MetabindContentAction) -> Void
    
    @Environment(\.bindJS) private var config
    
    func body(content: Content) -> some View {
        var newConfig = config
        newConfig.onAction = { action in
            body(MetabindContentAction(name: action.name, props: action.props))
        }
        return content.environment(\.bindJS, newConfig)
    }
}
