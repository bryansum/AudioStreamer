//
//  Downloader.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import os.log

/// The `Downloader` is a concrete implementation of the `Downloading` protocol
/// using `URLSession` as the backing HTTP/HTTPS implementation.
public class Downloader: NSObject, Downloading {
    static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "Downloader")

    // MARK: - Singleton

    /// A singleton that can be used to perform multiple download requests using a common cache.
    public static var shared: Downloader = .init()

    // MARK: - Properties

    /// A `Bool` indicating whether the session should use the shared URL cache or not. Really useful for testing, but in production environments you probably always want this to `true`. Default is true.
    public var useCache = true {
        didSet {
            session.configuration.urlCache = useCache ? URLCache.shared : nil
        }
    }

    private lazy var queue = DispatchQueue(label: "com.fastlearner.streamer.Downloader")

    /// The `URLSession` currently being used as the HTTP/HTTPS implementation for the downloader.
    fileprivate lazy var session: URLSession = .init(
        configuration: .default,
        delegate: self,
        delegateQueue: {
            let operationQueue = OperationQueue()
            operationQueue.underlyingQueue = queue
            return operationQueue
        }()
    )

    /// A `URLSessionDataTask` representing the data operation for the current `URL`.
    fileprivate var task: URLSessionDataTask?

    /// A `Int64` representing the total amount of bytes received
    var totalBytesReceived: Int64 = 0

    /// A `Int64` representing the total amount of bytes for the entire file
    var totalBytesCount: Int64 = 0

    // MARK: - Properties (Downloading)

    public var delegate: DownloadingDelegate?
    public var completionHandler: ((Error?) -> Void)?
    public var progressHandler: ((Data, Float) -> Void)?
    public var progress: Float = 0
    public var state: DownloadingState = .notStarted {
        didSet {
            delegate?.download(self, changedState: state)
        }
    }

    /// These fields will be added to a URL request. Must be specified before setting `url`.
    public var headerFields: [String: String]?

    public var url: URL? {
        didSet {
            if state == .started {
                stop()
            }

            if let url {
                progress = 0.0
                state = .notStarted
                totalBytesCount = 0
                totalBytesReceived = 0

                if url.isFileURL {
                    // If it's a file URL, we don't need a task.
                    task = nil
                } else {
                    var request = URLRequest(url: url)
                    if let headerFields {
                        for (key, value) in headerFields {
                            request.setValue(value, forHTTPHeaderField: key)
                        }
                    }
                    task = session.dataTask(
                        with: request
                    )
                }
            } else {
                task = nil
            }
        }
    }

    // MARK: - Methods

    public func start() {
        os_log("%@ - %d [%@]", log: Downloader.logger, type: .debug, #function, #line, String(describing: url))

        if let url, url.isFileURL {
            queue.async { [self] in
                // Handle local file URL
                do {
                    let data = try Data(contentsOf: url)
                    DispatchQueue.main.async { [self] in
                        totalBytesCount = Int64(data.count)
                        totalBytesReceived = Int64(data.count)
                        progress = 1.0

                        // Call progress and completion handlers.
                        progressHandler?(data, progress)
                        state = .completed
                        completionHandler?(nil)
                        delegate?.download(self, completedWithError: nil)
                    }
                } catch {
                    DispatchQueue.main.async { [self] in
                        state = .completed
                        completionHandler?(error)
                        delegate?.download(self, completedWithError: error)
                    }
                }
            }
        } else {
            guard let task else {
                return
            }

            switch state {
            case .completed, .started:
                return
            default:
                state = .started
                task.resume()
            }
        }
    }

    public func pause() {
        os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line)

        guard let task else {
            return
        }

        guard state == .started else {
            return
        }

        state = .paused
        task.suspend()
    }

    public func stop() {
        os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line)

        guard let task else {
            return
        }

        guard state == .started else {
            return
        }

        state = .stopped
        task.cancel()
    }
}
