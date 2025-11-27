//
//  BoopViewModel.swift
//  boop-ios
//

import Combine
import Foundation
import UIKit
import SwiftData

@MainActor
class BoopViewModel: NSObject, ObservableObject {
    private var boopManager: BoopManager
    private var cancellables = Set<AnyCancellable>()
    @Published var boopAnimationQueue: [UUID] = []
    @Published var hadErrorBooping: Bool = false
    
    override init() {
        self.boopManager = BoopManager(
            bluetoothManager: BluetoothManager(
                uwbManager: UWBManager()))
        super.init()
        self.setupObservers()
        
    }
    
    private func setupObservers()
    {
        boopManager.$boopQueue
            .sink { [weak self] boopQueue in
            guard let self = self else { return }
                self.updateAnimationQueue(boopQueue: boopQueue)
        }
        .store(in: &cancellables)
    }
    
    private func updateAnimationQueue(boopQueue: [UUID]) {
        if !boopQueue.isEmpty {
            do {
                let user = try boopManager.boopAndRemove()
                boopAnimationQueue.append(user)
                
            } catch {
                hadErrorBooping = true
            }
        }
    }
    
    func getBoopUserFromAnimationQueueAndRemove() -> String {
        return boopAnimationQueue.popLast()?.uuidString ?? ""
    }
    
    func getLastBoopUserFromAnimationQueue() -> String {
        return boopAnimationQueue.last?.uuidString ?? ""
    }

}
