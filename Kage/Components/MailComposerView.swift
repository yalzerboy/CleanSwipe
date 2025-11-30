//
//  MailComposerView.swift
//  Kage
//
//  Created by GPT-5 Codex on 10/11/2025.
//

import MessageUI
import SwiftUI

struct MailComposerView: UIViewControllerRepresentable {
    typealias ResultHandler = (Result<MFMailComposeResult, Error>) -> Void
    
    var subject: String
    var recipients: [String]
    var body: String?
    var isHTML: Bool
    var resultHandler: ResultHandler?
    
    init(
        subject: String,
        recipients: [String],
        body: String? = nil,
        isHTML: Bool = false,
        resultHandler: ResultHandler? = nil
    ) {
        self.subject = subject
        self.recipients = recipients
        self.body = body
        self.isHTML = isHTML
        self.resultHandler = resultHandler
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setToRecipients(recipients)
        if let body {
            controller.setMessageBody(body, isHTML: isHTML)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No-op
    }
    
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let parent: MailComposerView
        
        init(parent: MailComposerView) {
            self.parent = parent
        }
        
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            defer {
                controller.dismiss(animated: true)
            }
            
            if let error {
                parent.resultHandler?(.failure(error))
            } else {
                parent.resultHandler?(.success(result))
            }
        }
    }
}


