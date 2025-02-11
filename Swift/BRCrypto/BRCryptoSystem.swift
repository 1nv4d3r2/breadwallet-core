//
//  BRSystemSystem.swift
//  BRCrypto
//
//  Created by Ed Gamble on 3/27/19.
//  Copyright © 2019 Breadwinner AG. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//  See the CONTRIBUTORS file at the project root for a list of contributors.
//
import Foundation  // Data, DispatchQueue
import BRCryptoC

///
/// System (a singleton)
///
public final class System {

    /// The listener.  Gets all events for {Network, WalletManger, Wallet, Transfer}
    public private(set) weak var listener: SystemListener?

    /// The listenerQueue where all listener 'handle events' are asynchronously performed.
    internal let listenerQueue: DispatchQueue

    /// The account
    public let account: Account

    /// The path for persistent storage
    public let path: String

    /// If on mainnet
    public let onMainnet: Bool

    /// The 'blockchain DB' to use for BRD Server Assisted queries
    public let query: BlockChainDB

    /// The queue for asynchronous functionality.  Notably this is used in `configure()` to
    /// gather all of the `query` results as Networks are created and added.
    internal let queue = DispatchQueue (label: "Crypto System")

    /// the networks, unsorted.
    public internal(set) var networks: [Network] = []

    /// Flag indicating if the network is reachable; defaults to true
    internal var isNetworkReachable = true

    /// The wallet managers, unsorted.  A WalletManager will hold an 'unowned'
    /// reference back to `System`
    public internal(set) var managers: [WalletManager] = [];

    internal let callbackCoordinator: SystemCallbackCoordinator

    /// We define default blockchains but these are wholly insufficient given that the
    /// specfication includes `blockHeight` (which can never be correct).

    static let supportedBlockchains: [BlockChainDB.Model.Blockchain] = [
        // Mainnet
        (id: "bitcoin-mainnet",      name: "Bitcoin",      network: "mainnet", isMainnet: true,  currency: "bitcoin-mainnet:__native__",     blockHeight: 595000,
         feeEstimates: [(amount: "30", tier: "10m", confirmationTimeInMilliseconds: 10 * 60 * 1000)],
         confirmationsUntilFinal: 6),
        (id: "bitcoincash-mainnet",  name: "Bitcoin Cash", network: "mainnet", isMainnet: true,  currency: "bitcoincash-mainnet:__native__", blockHeight: 600000,
         feeEstimates: [(amount: "30", tier: "10m", confirmationTimeInMilliseconds: 10 * 60 * 1000)],
         confirmationsUntilFinal: 6),
        (id: "ethereum-mainnet",     name: "Ethereum",     network: "mainnet", isMainnet: true,  currency: "ethereum-mainnet:__native__",    blockHeight: 8570000,
         feeEstimates: [(amount: "2000000000", tier: "1m", confirmationTimeInMilliseconds: 1 * 60 * 1000)],
         confirmationsUntilFinal: 6),
//        (id: "ripple-mainnet",        name: "Ripple",        network: "mainnet", isMainnet: true,  currency: "xrp", blockHeight: nil,
//         feeEstimates: [(amount: "20", tier: "1m", confirmationTimeInMilliseconds: 1 * 60 * 1000)]),

        // Testnet
        (id: "bitcoin-testnet",      name: "Bitcoin Testnet",      network: "testnet", isMainnet: false, currency: "bitcoin-testnet:__native__",     blockHeight: 1575000,
         feeEstimates: [(amount: "30", tier: "10m", confirmationTimeInMilliseconds: 10 * 60 * 1000)],
         confirmationsUntilFinal: 6),
        (id: "bitcoincash-testnet",  name: "Bitcoin Cash Testnet", network: "testnet", isMainnet: false, currency: "bitcoincash-testnet:__native__", blockHeight: 1325000,
         feeEstimates: [(amount: "30", tier: "10m", confirmationTimeInMilliseconds: 10 * 60 * 1000)],
         confirmationsUntilFinal: 6),
        (id: "ethereum-ropsten",     name: "Ethereum Ropsten",     network: "testnet", isMainnet: false, currency: "ethereum-ropsten:__native__",    blockHeight: 6415000,
         feeEstimates: [(amount: "2000000000", tier: "1m", confirmationTimeInMilliseconds: 1 * 60 * 1000)],
         confirmationsUntilFinal: 6),
//        (id: "ripple-testnet",        name: "Ripple Testnet",    network: "testnet", isMainnet: false, currency: "xrp", blockHeight: nil,
//         feeEstimates: [(amount: "20", tier: "1m", confirmationTimeInMilliseconds: 1 * 60 * 1000)]),
    ]

    private static func makeCurrencyIdentifierERC20 (_ blockchainID: String, _ address: String) -> String {
        return "\(blockchainID):\(address)"
    }

    private static func makeCurrencyDemominationsERC20 (_ code: String, decimals: UInt8) -> [BlockChainDB.Model.CurrencyDenomination] {
        let name = code.uppercased()
        let code = code.lowercased()

        return [
            (name: "\(name) Token INT", code: "\(code)i", decimals: 0,        symbol: "\(code)i"),   // BRDI -> BaseUnit
            (name: "\(name) Token",     code: code,       decimals: decimals, symbol: code)
        ]
    }

    static let defaultCurrencies: [BlockChainDB.Model.Currency] = [
        // Mainnet
        (id: "bitcoin-mainnet:__native__", name: "Bitcoin", code: "btc", type: "native", blockchainID: "bitcoin-mainnet",
         address: nil, verified: true,
         demoninations: [(name: "Satoshi", code: "sat", decimals: 0, symbol: BlockChainDB.Model.lookupSymbol ("sat")),
                         (name: "Bitcoin", code: "btc", decimals: 8, symbol: BlockChainDB.Model.lookupSymbol ("btc"))]),

        (id: "bitcoincash-mainnet:__native__", name: "Bitcoin Cash", code: "bch", type: "native", blockchainID: "bitcoincash-mainnet",
         address: nil, verified: true,
         demoninations: [(name: "Satoshi",      code: "sat", decimals: 0, symbol: BlockChainDB.Model.lookupSymbol ("sat")),
                         (name: "Bitcoin Cash", code: "bch", decimals: 8, symbol: BlockChainDB.Model.lookupSymbol ("bch"))]),

        (id: "ethereum-mainnet:__native__", name: "Ethereum", code: "eth", type: "native", blockchainID: "ethereum-mainnet",
         address: nil, verified: true,
         demoninations: [(name: "Wei",   code: "wei",  decimals:  0, symbol: BlockChainDB.Model.lookupSymbol ("wei")),
                         (name: "Gwei",  code: "gwei", decimals:  9, symbol: BlockChainDB.Model.lookupSymbol ("gwei")),
                         (name: "Ether", code: "eth",  decimals: 18, symbol: BlockChainDB.Model.lookupSymbol ("eth"))]),

        (id: System.makeCurrencyIdentifierERC20 ("ethereum-mainnet", BlockChainDB.Model.addressBRDMainnet), name: "BRD Token", code: "brd", type: "erc20", blockchainID: "ethereum-mainnet",
         address: BlockChainDB.Model.addressBRDMainnet, verified: true,
         demoninations: System.makeCurrencyDemominationsERC20 ("brd", decimals: 18)),

//        (id: "EOS Token", name: "EOS Token", code: "eos", type: "erc20", blockchainID: "ethereum-mainnet",
//         address: "0x86fa049857e0209aa7d9e616f7eb3b3b78ecfdb0", verified: true,
//         demoninations: [(name: "EOS INT, code: "eos1",  decimals:  0, symbol: "eosi"),
//                         (name: "EOS",    code: "eos",   decimals: 18, symbol: "eos")]),

//        (id: "Ripple", name: "Ripple", code: "xrp", type: "native", blockchainID: "ripple-mainnet",
//         address: nil, verified: true,
//         demoninations: [(name: "drop", code: "drop", decimals: 0, symbol: "drop"),
//                         (name: "xrp",  code: "xrp",  decimals: 6, symbol: "xrp")]),

        // Testnet
        (id: "bitcoin-testnet:__native__", name: "Bitcoin Testnet", code: "btc", type: "native", blockchainID: "bitcoin-testnet",
         address: nil, verified: true,
         demoninations: [(name: "Satoshi",         code: "sat",         decimals: 0, symbol: BlockChainDB.Model.lookupSymbol ("sat")),
                         (name: "Bitcoin Testnet", code: "btc", decimals: 8, symbol: BlockChainDB.Model.lookupSymbol ("btc"))]),

        (id: "bitcoincash-testnet:__native__", name: "Bitcoin Cash Testnet", code: "bch", type: "native", blockchainID: "bitcoincash-testnet",
         address: nil, verified: true,
         demoninations: [(name: "Satoshi",              code: "sat",          decimals: 0, symbol: BlockChainDB.Model.lookupSymbol ("sat")),
                         (name: "Bitcoin Cash Testnet", code: "bch", decimals: 8, symbol: BlockChainDB.Model.lookupSymbol ("bch"))]),

        (id: "ethereum-ropsten:__native__", name: "Ethereum Ropsten", code: "eth", type: "native", blockchainID: "ethereum-ropsten",
         address: nil, verified: true,
         demoninations: [(name: "Wei",   code: "wei",  decimals:  0, symbol: BlockChainDB.Model.lookupSymbol ("wei")),
                         (name: "Gwei",  code: "gwei", decimals:  9, symbol: BlockChainDB.Model.lookupSymbol ("gwei")),
                         (name: "Ether", code: "eth",  decimals: 18, symbol: BlockChainDB.Model.lookupSymbol ("eth"))]),

        (id: System.makeCurrencyIdentifierERC20 ("ethereum-ropsten", BlockChainDB.Model.addressBRDTestnet), name: "BRD Token Testnet", code: "brd", type: "erc20", blockchainID: "ethereum-ropsten",
         address: BlockChainDB.Model.addressBRDTestnet, verified: true,
         demoninations: System.makeCurrencyDemominationsERC20 ("brd", decimals: 18)),

//        (id: "Ripple", name: "Ripple", code: "xrp", type: "native", blockchainID: "ripple-testnet",
//         address: nil, verified: true,
//         demoninations: [(name: "drop", code: "drop", decimals: 0, symbol: "drop"),
//                         (name: "xrp",  code: "xrp",  decimals: 6, symbol: "xrp")]),
    ]

    ///
    /// Address Scheme
    ///

    static let supportedAddressSchemesMap: [String:[AddressScheme]] = [
        "bitcoin-mainnet":      [.btcSegwit, .btcLegacy],
        "bitcoincash-mainnet": [.btcLegacy],
        "ethereum-mainnet":     [.ethDefault],
        "ripple-mainnet":       [.genDefault],
        "bitcoin-testnet":      [.btcSegwit, .btcLegacy],
        "bitcoincash-testnet":  [.btcLegacy],
        "ethereum-ropsten":     [.ethDefault],
//        "ripple-testnet":       [.genDefault]
    ]

    static let defaultAddressSchemeMap: [String:AddressScheme] = [
        "bitcoin-mainnet":      .btcSegwit,
        "bitcoincash-mainnet": .btcLegacy,
        "ethereum-mainnet":     .ethDefault,
        "ripple-mainnet":       .genDefault,
        "bitcoin-testnet":      .btcSegwit,
        "bitcoincash-testnet":  .btcLegacy,
        "ethereum-ropsten":     .ethDefault,
//        "ripple-testnet":       .genDefault
    ]

    ///
    /// Return the AddressSchemes support for `network`
    ///
    /// - Parameter network: the network
    ///
    /// - Returns: An array of AddressScheme
    ///
    public func supportedAddressSchemes (network: Network) -> [AddressScheme] {
        return System.supportedAddressSchemesMap[network.uids] ?? [.genDefault]
    }

    ///
    /// Check if `network` supports `scheme`
    ///
    /// - Parameters:
    ///   - network: the network
    ///   - scheme: the scheme
    ///
    /// - Returns: If supported `true`; otherwise `false`.
    ///
    public func supportsAddressScheme (network: Network, _ scheme: AddressScheme) -> Bool {
        return supportedAddressSchemes(network: network).contains (scheme)
    }

    ///
    /// Return the default AddressScheme for `network`
    ///
    /// - Parameter network: the network
    ///
    /// - Returns: The default AddressScheme
    ///
    public func defaultAddressScheme (network: Network) -> AddressScheme {
        return System.defaultAddressSchemeMap[network.uids] ?? .genDefault
    }

    ///
    /// Wallet Manager Modes
    ///
    /// Blockchains with built-in P2P support (BTC, BCH, and ETH) may support `.p2p_only`.
    /// Intermediate modes (.api_with_p2p_submit, .p2p_with_api_sync) are suppored on a case-by-case
    /// basis. API mode is supported if BRD infrastructure supports that blockchain (for example,
    /// BCH is not at the moment)
    ///
    /// It is possible that the `.api_only` mode does not work - for exmaple, the BDB is down.  In
    /// that case it is an App issue to report and resolve the issue by: waiting out the outage;
    /// selecting another mode if available.
    ///
    /// These values are updated whenever the BDB support updates.  However, a given WalletKit
    /// distribution in the wild might be out of date with the current BDB support.  That can mean
    /// that some API mode is missing here that a new BDB support (like when BCH comes online) or
    /// that a mode has disappeared (maybe a blockchain is dropped).  These cases are not
    /// destructive.
    ///
    static let supportedModesMap: [String:[WalletManagerMode]] = [
        "bitcoin-mainnet":      [.api_only, .p2p_only],
        "bitcoincash-mainnet":  [.p2p_only],
        "ethereum-mainnet":     [.api_only, .api_with_p2p_submit, .p2p_only],
//        "ripple-mainnet":       [],
        "bitcoin-testnet":      [.api_only, .p2p_only],
        "bitcoincash-testnet":  [.p2p_only],
        "ethereum-ropsten":     [.api_only, .api_with_p2p_submit, .p2p_only],
//        "ripple-testnet":       []
    ]

    ///
    /// The default Modes
    ///
    static let defaultModesMap: [String:WalletManagerMode] = [
        "bitcoin-mainnet":      .p2p_only,
        "bitcoincash-mainnet":  .p2p_only,
        "ethereum-mainnet":     .api_only,
//        "ripple-mainnet":       [],
        "bitcoin-testnet":      .p2p_only,
        "bitcoincash-testnet":  .p2p_only,
        "ethereum-ropsten":     .api_only,
//        "ripple-testnet":       []
    ]


    /// Return the WalletManagerModes supported by `network`
    ///
    /// - Parameter network: the network
    ///
    /// - Returns: an aray of WalletManagerMode
    ///
    public func supportedModes (network: Network) -> [WalletManagerMode] {
        return System.supportedModesMap[network.uids] ?? [.api_only]
    }

    ///
    /// Check if `network` supports `mode`
    ///
    /// - Parameters:
    ///   - network: the network
    ///   - mode: the mode
    ///
    /// - Returns: If supported `true`; otherwise `false`
    ///
    public func supportsMode (network: Network, _ mode: WalletManagerMode) -> Bool {
        return supportedModes (network: network).contains (mode)
    }

    ///
    /// Return the default WalletManagerMode for `network`
    ///
    /// - Parameter network: the network
    ///
    /// - Returns: the default mode
    ///
    public func defaultMode (network: Network) -> WalletManagerMode {
        return System.defaultModesMap[network.uids] ?? .api_only
    }

    ///
    /// Add `network` to `networks`
    ///
    /// - Parameter network: the network to add
    ///
    internal func add (network: Network) {
        networks.append (network)
        announceEvent (SystemEvent.networkAdded(network: network))
    }

    internal func networkBy (uids: String) -> Network? {
        return networks.first { $0.uids == uids }
    }

     internal func managerBy (core: BRCryptoWalletManager) -> WalletManager? {
        return managers
            .first { $0.core == core }
    }

    ///
    /// Add `manager` to `managers`.  Will signal WalletManagerEvent.created and then
    /// SystemEvent.managerAdded is `manager` is added.
    ///
    /// - Parameter manager: the manager to add.
    ///
    internal func add (manager: WalletManager) {
        if !managers.contains(where: { $0 === manager }) {
            managers.append (manager)
            announceEvent (SystemEvent.managerAdded(manager: manager))
        }
    }

    ///
    /// Create a wallet manager for `network` using `mode`, `addressScheme`, and `currencies`.  A
    /// wallet will be 'registered' for each of:
    ///    a) the network's currency - this is the primaryWallet
    ///    b) for each of `currences` that are in `network`.
    /// These wallets are announced using WalletEvent.created and WalletManagerEvent.walledAdded.
    ///
    /// The created wallet manager is announed using WalletManagerEvent.created and
    /// SystemEvent.managerAdded.
    ///
    /// - Parameters:
    ///   - network: the wallet manager's network
    ///   - mode: the wallet manager mode to use
    ///   - addressScheme: the address scheme to use
    ///   - currencies: the currencies to 'register'.  A wallet will be created for each one.  It
    ///       is safe to pass currencies not in `network` as they will be filtered (but bad form
    ///       to do so).  The 'primaryWallet', for the network's currency, is always created; if
    ///       the primaryWallet's currency is in `currencies` then it is effectively ignored.
    ///
    /// - Returns: `true` on success; `false` on failure.
    ///
    /// - Note: There are two preconditions - `network` must support `mode` and `addressScheme`.
    ///     Thus a fatal error arises if, for example, the network is BTC and the scheme is ETH.
    ///
    public func createWalletManager (network: Network,
                                     mode: WalletManagerMode,
                                     addressScheme: AddressScheme,
                                     currencies: Set<Currency>) -> Bool {
        precondition (supportsMode(network: network, mode))
        precondition (supportsAddressScheme(network: network, addressScheme))

        guard let manager = WalletManager (system: self,
                                           callbackCoordinator: callbackCoordinator,
                                           account: account,
                                           network: network,
                                           mode: mode,
                                           addressScheme: addressScheme,
                                           currencies: currencies,
                                           storagePath: path,
                                           listener: cryptoListener,
                                           client: cryptoClient)
            else { return false }
        
        manager.setNetworkReachable(isNetworkReachable)
        self.add (manager: manager)
        return true
    }

    ///
    /// Remove (aka 'wipe') the persistent storage associated with `network` at `path`.  This should
    /// be used solely to recover from a failure of `createWalletManager`.  A failure to create
    /// a wallet manager is most likely due to corruption of the persistently stored data and the
    /// only way to recover is to wipe that data.
    ///
    /// - Parameters:
    ///   - network: network to wipe data for
    ///
    public func wipe (network: Network) {
        // Racy - but if there is no wallet manager for `network`... then
        if !managers.contains { network == $0.network } {
            cryptoWalletManagerWipe (network.core, path);
        }
    }

    // Wallets - derived as a 'flatMap' of the managers' wallets.
    public var wallets: [Wallet] {
        return managers.flatMap { $0.wallets }
    }

    static func ensurePath (_ path: String) -> Bool {
        // Apple on `fileExists`, `isWritableFile`
        //    "The following methods are of limited utility. Attempting to predicate behavior
        //     based on the current state of the filesystem or a particular file on the filesystem
        //     is encouraging odd behavior in the face of filesystem race conditions. It's far
        //     better to attempt an operation (like loading a file or creating a directory) and
        //     handle the error gracefully than it is to try to figure out ahead of time whether
        //     the operation will succeed."

        do {
            // Ensure that `storagePath` exists.  Seems the return value can be ignore:
            //    "true if the directory was created, true if createIntermediates is set and the
            //     directory already exists, or false if an error occurred."
            // The `attributes` need not be provided as we have write permission :
            //    "Permissions are set according to the umask of the current process"
            try FileManager.default.createDirectory (atPath: path,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
        }
        catch { return false }

        // Ensure `path` is writeable.
        return FileManager.default.isWritableFile (atPath: path)
    }

    ///
    /// Initialize System
    ///
    /// - Parameters:
    ///   - listener: The listener for handlng events.
    ///
    ///   - account: The account, derived from the `paperKey`, that will be used for all networks.
    ///
    ///   - onMainnet: boolean to indicate if this is for mainnet or for testnet.  As blockchains
    ///       are announced, we'll filter them to be for mainent or testnet.
    ///
    ///   - path: The path to use for persistent storage of data, such as for BTC and ETH blocks,
    ///       peers, transaction and logs.
    ///
    ///   - query: The query for BlockchiainDB interaction.
    ///
    ///   - listenerQueue: The queue to use when performing listen event handler callbacks.  If a
    ///       queue is not specficied (default to `nil`), then one will be provided.
    ///
    internal init (listener: SystemListener,
                  account: Account,
                  onMainnet: Bool,
                  path: String,
                  query: BlockChainDB,
                  listenerQueue: DispatchQueue? = nil) {
        let accounctSpecificPath = path + (path.last == "/" ? "" : "/") + account.fileSystemIdentifier
        precondition (System.ensurePath(accounctSpecificPath))

        self.listener  = listener
        self.account   = account
        self.onMainnet = onMainnet
        self.path  = accounctSpecificPath
        self.query = query
        self.listenerQueue = listenerQueue ?? DispatchQueue (label: "Crypto System Listener")
        self.callbackCoordinator = SystemCallbackCoordinator (queue: self.listenerQueue)

        System.systemExtend (with: self)
        announceEvent(SystemEvent.created)
    }

    internal func announceEvent (_ event: SystemEvent) {
        self.listenerQueue.async {
            self.listener?.handleSystemEvent (system: self,
                                              event: event)
        }
    }

    ///
    /// Subscribe (or unsubscribe) to BlockChainDB notifications.  Notifications provide an
    /// asynchronous announcement of DB changes pertinent to the User and are used to avoid
    /// polling the DB for such changes.
    ///
    /// The Subscription includes an `endpoint` which is optional.  If provided, subscriptions
    /// are enabled; if not provided, subscriptions are disabled.  Disabling a sbuscription is
    /// required, even though polling in undesirable, because Notifications are user configured.
    ///
    /// - Parameter subscription: the subscription to enable or to disable notifications
    ///
    public func subscribe (using subscription: BlockChainDB.Subscription) {
        self.query.subscribe (walletId: account.uids,
                              subscription: subscription)
    }

    ///
    /// Announce a BlockChainDB transaction.  This should be called upon the "System User's"
    /// receipt of a BlockchainDB notification.
    ///
    /// - Parameters:
    ///   - transaction: the transaction id which can be used in `getTransfer` to query the
    ///         blockchainDB for details on the transaction
    ///   - data: The transaction JSON data (a dictionary) if available
    ///
    public func announce (transaction id: String, data: [String: Any]) {
        print ("SYS: Announce: \(id)")
    }
    #if false
    internal func updateSubscribedWallets () {
        let currencyKeyValues = wallets.map { ($0.currency.code, [$0.source.description]) }
        let wallet = (id: account.uids,
                      currencies: Dictionary (uniqueKeysWithValues: currencyKeyValues))
        self.query.updateWallet (wallet) { (res: Result<BlockChainDB.Model.Wallet, BlockChainDB.QueryError>) in
            print ("SYS: SubscribedWallets: \(res)")
        }
    }
    #endif
    /// MARK: - Network Fees

    ////
    /// A NetworkFeeUpdateError
    ///
    public enum NetworkFeeUpdateError: Error {
        /// The query endpoint for netowrk fees is unresponsive
        case feesUnavailable
    }

    ///
    /// Update the NetworkFees for all known networks.  This will query the `BlockChainDB` to
    /// acquire the fee information and then update each of system's networks with the new fee
    /// structure.  Each updated network will generate a NetworkEvent.feesUpdated event (even if
    /// the actual fees did not change).
    ///
    /// And optional completion handler can be provided.  If provided the completion handler is
    /// invoked with an array of the networks that were updated or with an error.
    ///
    /// It is appropriate to call this function anytime a network's fees are to be used, such as
    /// when a transfer is created and the User can choose among the different fees.
    ///
    /// - Parameter completion: An optional completion handler
    ///
    public func updateNetworkFees (_ completion: ((Result<[Network],NetworkFeeUpdateError>) -> Void)? = nil) {
        self.query.getBlockchains (mainnet: self.onMainnet) {
            (blockChainResult: Result<[BlockChainDB.Model.Blockchain],BlockChainDB.QueryError>) in

            // On an error, just skip out; we'll query again later, presumably
            guard case let .success (blockChainModels) = blockChainResult
                else {
                    completion? (Result.failure (NetworkFeeUpdateError.feesUnavailable))
                    return
            }

            let networks = blockChainModels.compactMap { (blockChainModel: BlockChainDB.Model.Blockchain) -> Network? in
                guard let network = self.networkBy (uids: blockChainModel.id)
                    else { return nil }

                // We always have a feeUnit for network
                let feeUnit = network.baseUnitFor(currency: network.currency)!

                // Get the fees
                let fees = blockChainModel.feeEstimates
                    // Well, quietly ignore a fee if we can't parse the amount.
                    .compactMap { (fee: BlockChainDB.Model.BlockchainFee) -> NetworkFee? in
                        return Amount.create (string: fee.amount, unit: feeUnit)
                            .map { NetworkFee (timeIntervalInMilliseconds: fee.confirmationTimeInMilliseconds,
                                               pricePerCostFactor: $0) }
                }

                // The fees are unlikely to change; but we'll announce .feesUpdated anyways.
                network.fees = fees
                self.listenerQueue.async {
                    self.listener?.handleNetworkEvent (system: self, network: network, event: .feesUpdated)
                }

                return network
            }

            completion? (Result.success(networks))
        }
    }

    ///
    /// Disconnect all wallet managers
    ///
    public func disconnectAll () {
        managers.forEach { $0.disconnect() }
    }

    ///
    /// Connect all wallet managers.  They will be connected w/o an explict NetworkPeer.
    ///
    public func connectAll () {
        managers.forEach { $0.connect() }
    }

    ///
    /// Set the network reachable flag for all managers. Setting or clearing this flag will
    /// NOT result in a connect/disconnect operation by a manager. Callers must use the
    /// `connect`/`disconnect` calls to change a WalletManager's connectivity state. Instead,
    /// managers MAY consult this flag when performing network operations to determine their
    /// viability.
    ///
    public func setNetworkReachable (_ isNetworkReachable: Bool) {
        self.isNetworkReachable = isNetworkReachable
        managers.forEach { $0.setNetworkReachable(isNetworkReachable) }
    }

    private func configureMergeBlockchains (builtin: [BlockChainDB.Model.Blockchain],
                                            remote:  [BlockChainDB.Model.Blockchain]) -> [BlockChainDB.Model.Blockchain] {
        // We ONLY support built-in blockchains; but the remotes have some
        // needed values - specifically the network fees.

        // Filter `remote` to only include `builtin` block chains.  Thus `remote` will never have
        // more than `builtin` but might have less.
        let supportedRemote = remote.filter { item in builtin.contains(where: { $0.id == item.id } ) }

        // Augment `remote` to include all `builtin`.
        return supportedRemote.unionOf(builtin) { $0.id }
            // Keep all the `remote` data as valid BUT ensure there is a blockHeight
            .map { (rbc) in
                // If we have a block height, then no update is required.
                guard nil == rbc.blockHeight else { return rbc }

                // By construction we have a builtin blockchain
                let bbc = builtin.first (where: { $0.id == rbc.id })! // ! => must have

                // The builtin blockchain as a blockHeight; the remote does not -> update it.
                return BlockChainDB.Model.updateBlockchainModelHeight (model: rbc, height: bbc.blockHeight!)
        }
    }

    ///
    /// Configure the system.  This will query various BRD services, notably the BlockChainDB, to
    /// establish the available networks (aka blockchains) and their currencies.  For each
    /// `Network` there will be `SystemEvent` which can be used by the App to create a
    /// `WalletManager`
    ///
    /// - Parameter applicationCurrencies: If the BlockChainDB does not return any currencies, then
    ///     use `applicationCurrencies` merged into the deafults.  Appropriate currencies can be
    ///     created from `System::asBlockChainDBModelCurrency` (see below)
    ///
    public func configure (withCurrencyModels applicationCurrencies: [BlockChainDB.Model.Currency]) {
        func currencyDenominationToBaseUnit (currency: Currency, model: BlockChainDB.Model.CurrencyDenomination) -> Unit {
            let uids = "\(currency.uids):\(model.code)"
            return Unit (currency: currency, uids: uids, name: model.name, symbol: model.symbol)
        }

        func currencyToDefaultBaseUnit (currency: Currency) -> Unit {
            let symb = "\(currency.code)I".lowercased()
            let name = "\(currency.code) INT".uppercased()
            let uids = "\(currency.uids):\(name)"
            return Unit (currency: currency, uids: uids, name: name, symbol: symb)
        }

        func currencyDenominationToUnit (currency: Currency, model: BlockChainDB.Model.CurrencyDenomination, base: Unit) -> Unit {
            let uids = "\(currency.uids):\(model.code)"
            return Unit (currency: currency, uids: uids, name: model.name, symbol: model.symbol, base: base, decimals: model.decimals)
        }

        // Query for blockchains on the system.queue - thus system.configure() returns instantly
        // and only System (and other types of) Events allow access to networds, wallets, etc.
        self.queue.async {
            // This semaphore is used only to block this async block until at least one group
            // is entered.  Then this async block will wait until all groups have been left.
            let blockchainsSemaphore = DispatchSemaphore (value: 0)

            // This group will be entered and left multiple times as blockchain models and their
            // currencies are processed
            let blockchainsGroup = DispatchGroup ()

            var discoveredNetworks:[Network] = []

            // query blockchains
            self.query.getBlockchains (mainnet: self.onMainnet) { (blockchainResult: Result<[BlockChainDB.Model.Blockchain],BlockChainDB.QueryError>) in
                // Filter our defaults to be `self.onMainnet` and supported (non-nil blockHeight)
                let blockChainModelsSupported = System.supportedBlockchains
                    .filter { $0.isMainnet == self.onMainnet && nil != $0.blockHeight }

                // Get the remote block chains, some of these will be unsupported (have a nil
                // blockHeight).  We don't filter unsupported block chains because the BDB provides
                // valid network fee data.  We'll merge 'supported' and 'remote'
                let blockChainModelsRemote = blockchainResult
                    .getWithRecovery { (ignore) in return [] }

                let blockChainModels =
                    self.configureMergeBlockchains (builtin: blockChainModelsSupported,
                                                    remote: blockChainModelsRemote)

                // If there are no models, then we are done (and disappointed).
                guard !blockChainModels.isEmpty
                    else { blockchainsSemaphore.signal(); return }

                // Enter the group once for each model; we'll leave as each currency is processed.
                // when all have left, self.queue will unblock
                blockChainModels.forEach { (ignore) in blockchainsGroup.enter() }

                // Signal the dispatch semaphore, the self.queue will now start blocking
                // on the dispatch group.
                blockchainsSemaphore.signal()

                // Handle each blockchain Model - there will be at least one model
                blockChainModels
                    .forEach { (blockchainModel: BlockChainDB.Model.Blockchain) in
                        // query currencies
                        self.query.getCurrencies (blockchainId: blockchainModel.id) { (currencyResult: Result<[BlockChainDB.Model.Currency],BlockChainDB.QueryError>) in
                            // We get one `currencyResult` per blockchain.  If we leave the group
                            // upon completion of this block, we'll match the `enter` calls.
                            defer { blockchainsGroup.leave() }

                            // Find applicable defaults by `blockchainID`
                            let defaults = System.defaultCurrencies
                                .filter { $0.blockchainID == blockchainModel.id }

                            // Find applicable application currencies by `blockchainID`
                            let apps = applicationCurrencies
                                .filter { $0.blockchainID == blockchainModel.id }

                            // Merge in `defaults` with the result; but, on error, use apps
                            let currencyModels = currencyResult
                                // On success, always merge `default` INTO the result.  We merge
                                // into `result` to always bias to the blockchainDB result.
                                .map { $0.unionOf (defaults) { $0.id }}

                                // On error, use `apps` merged INTO defaults.  We merge into
                                // `defaults` to ensure that we get BTC, BCH, ETH, BRD and that
                                // they are correct (don't rely on the App).
                                .getWithRecovery { (_) in return defaults.unionOf(apps) { $0.id } }

                            var associations: [Currency : Network.Association] = [:]

                            // Update associations
                            currencyModels
                                // TODO: Only needed if getCurrencies returns the wrong stuff.
                                .filter { $0.blockchainID == blockchainModel.id }
                                .filter { $0.verified }
                                .forEach { (currencyModel: BlockChainDB.Model.Currency) in
                                    // Create the currency
                                    let currency = Currency (uids: currencyModel.id,
                                                             name: currencyModel.name,
                                                             code: currencyModel.code,
                                                             type: currencyModel.type,
                                                             issuer: currencyModel.address)

                                    // Create the base unit
                                    let baseUnit: Unit = currencyModel.demoninations.first { 0 == $0.decimals }
                                        .map { currencyDenominationToBaseUnit(currency: currency, model: $0) }
                                        ?? currencyToDefaultBaseUnit (currency: currency)

                                    // Create the other units
                                    var units: [Unit] = [baseUnit]
                                    units += currencyModel.demoninations.filter { 0 != $0.decimals }
                                        .map { currencyDenominationToUnit (currency: currency, model: $0, base: baseUnit) }

                                    // Find the default unit
                                    let maximumDecimals = units.reduce (0) { max ($0, $1.decimals) }
                                    let defaultUnit = units.first { $0.decimals == maximumDecimals }!

                                    // Update associations
                                    associations[currency] = Network.Association (baseUnit: baseUnit,
                                                                                  defaultUnit: defaultUnit,
                                                                                  units: Set<Unit>(units))
                            }

                            // the default currency
                            guard let currency = associations.keys.first (where: { $0.uids == blockchainModel.currency.lowercased() }),
                                let feeUnit = associations[currency]?.baseUnit
                                else { print ("SYS: CONFIGURE: Missed Currency (\(blockchainModel.currency)) on '\(blockchainModel.network)': defaultUnit"); return }

                            // the network fees
                            let fees = blockchainModel.feeEstimates
                                // Well, quietly ignore a fee if we can't parse the amount.
                                .compactMap { (fee: BlockChainDB.Model.BlockchainFee) -> NetworkFee? in
                                    let timeInterval  = fee.confirmationTimeInMilliseconds
                                    return Amount.create (string: fee.amount, unit: feeUnit)
                                        .map { NetworkFee (timeIntervalInMilliseconds: timeInterval,
                                                           pricePerCostFactor: $0) }
                            }

                            // We require fees
                            guard !fees.isEmpty
                                else { print ("SYS: CONFIGURE: Missed Fees (\(blockchainModel.name)) on '\(blockchainModel.network)'"); return }

                            // Do not add a network that we've added already.
                            guard nil == self.networkBy (uids: blockchainModel.id)
                                else { print ("SYS: CONFIGURE: Skipped Duplicate Network: \(blockchainModel.name)"); return }

                            // define the network
                            let network = Network (uids: blockchainModel.id,
                                                   name: blockchainModel.name,
                                                   isMainnet: blockchainModel.isMainnet,
                                                   currency: currency,
                                                   height: blockchainModel.blockHeight!,
                                                   associations: associations,
                                                   fees: fees,
                                                   confirmationsUntilFinal: blockchainModel.confirmationsUntilFinal)

                            // Save the network
                            self.networks.append (network)

                            self.listenerQueue.async {
                                // Announce NetworkEvent.created...
                                self.listener?.handleNetworkEvent (system: self, network: network, event: NetworkEvent.created)

                                // Announce SystemEvent.networkAdded - this will likely be handled with
                                // system.createWalletManager(network:...) which will then announce
                                // numerous events as wallets are created.
                                self.listener?.handleSystemEvent  (system: self, event: SystemEvent.networkAdded(network: network))
                            }

                            // Keep a running total of discovered networks
                            discoveredNetworks.append(network)
                        }
                }
            }

            // Wait on the semaphore - indicates that the DispatchGroup is 'active'
            blockchainsSemaphore.wait()

            // Wait on the group - indicates that all models+currencies have entered and left.
            blockchainsGroup.wait()

            // Mark the completion.
            self.listenerQueue.async {
                self.listener?.handleSystemEvent(system: self, event: SystemEvent.discoveredNetworks (networks: discoveredNetworks))
            }
        }
    }

    ///
    /// Create a BlockChainDB.Model.Currency to be used in the event that the BlockChainDB does
    /// not provide its own currency model.
    ///
    public static func asBlockChainDBModelCurrency (uids: String, name: String, code: String, type: String, decimals: UInt8) -> BlockChainDB.Model.Currency? {
        // convert to lowercase to match up with built-in blockchains
        let type = type.lowercased()
        guard "erc20" == type || "native" == type else { return nil }
        return uids.firstIndex(of: ":")
            .map {
                let code         = code.lowercased()
                let blockchainID = uids.prefix(upTo: $0).description
                let address      = uids.suffix(from: uids.index (after: $0)).description

                return (id:   uids,
                        name: name,
                        code: code,
                        type: type,
                        blockchainID: blockchainID,
                        address: (address != "__native__" ? address : nil),
                        verified: true,
                        demoninations: System.makeCurrencyDemominationsERC20 (code, decimals: decimals))
        }
    }


    //
    // Static Weak System References
    //

    /// A serial queue to protect `systemIndex` and `systemMapping`
    static let systemQueue = DispatchQueue (label: "System", attributes: .concurrent)

    /// A index to globally identify systems.
    static var systemIndex: Int32 = 0;

    /// A dictionary mapping an index to a system.
    static var systemMapping: [Int32 : System] = [:]

    ///
    /// Lookup a `System` from an `index
    ///
    /// - Parameter index:
    ///
    /// - Returns: A System if it is mapped by the index and has not been GCed.
    ///
    static func systemLookup (index: Int32) -> System? {
        return systemQueue.sync {
            return systemMapping[index]
        }
    }

    /// An array of removed systems.  This is a workaround for systems that have been destroyed.
    /// We do not correctly handle 'release' and thus C-level memory issues are introduced; rather
    /// than solving those memory issues now, we'll avoid 'release' by holding a reference.
    private static var systemRemovedSystems = [System]()

    /// If true, save removed system in the above array. Set to `false` for debugging 'release'.
    private static var systemRemovedSystemsSave = true;

    static func systemRemove (index: Int32) {
        return systemQueue.sync (flags: .barrier) {
            systemMapping.removeValue (forKey: index)
                .map {
                    if systemRemovedSystemsSave {
                        systemRemovedSystems.append ($0)
                    }
            }
        }
    }

    ///
    /// Add a systme to the mapping.  Create a new index in the process and assign as system.index
    ///
    /// - Parameter system:
    ///
    /// - Returns: the system's index
    ///
    static func systemExtend (with system: System) {
        systemQueue.async (flags: .barrier) {
            systemIndex += 1
            system.index = systemIndex // Always 1 or more
            systemMapping[system.index] = system
        }
    }

    static func systemExtract (_ context: BRCryptoCWMListenerContext!,
                               _ cwm: BRCryptoWalletManager!) -> (System, WalletManager)? {
        precondition (nil != context  && nil != cwm)

        let index = 1 + Int32(UnsafeMutableRawPointer(bitPattern: 1)!.distance(to: context))

        return systemLookup(index: index)
            .map { ($0, WalletManager (core: cwm,
                                       system: $0,
                                       callbackCoordinator: $0.callbackCoordinator,
                                       take: true))
        }
    }

    static func systemExtract (_ context: BRCryptoCWMListenerContext!,
                               _ cwm: BRCryptoWalletManager!,
                               _ wid: BRCryptoWallet!) -> (System, WalletManager, Wallet)? {
        precondition (nil != context  && nil != cwm && nil != wid)

        return systemExtract (context, cwm)
            .map { ($0.0,
                    $0.1,
                    $0.1.walletByCoreOrCreate (wid, create: true)!)
        }
    }

    static func systemExtract (_ context: BRCryptoCWMListenerContext!,
                               _ cwm: BRCryptoWalletManager!,
                               _ wid: BRCryptoWallet!,
                               _ tid: BRCryptoTransfer!) -> (System, WalletManager, Wallet, Transfer)? {
        precondition (nil != context  && nil != cwm && nil != wid && nil != tid)

        // create -> CRYPTO_TRANSFER_EVENT_CREATED == event.type
        return systemExtract (context, cwm, wid)
            .map { ($0.0,
                    $0.1,
                    $0.2,
                    $0.2.transferByCoreOrCreate (tid, create: true)!)
        }
    }

    /// The index of this system
    var index: Int32 = 0

    var systemContext: BRCryptoCWMClientContext? {
        let index = Int(self.index)
        return UnsafeMutableRawPointer (bitPattern: index)
    }

    public static func create (listener: SystemListener,
                               account: Account,
                               onMainnet: Bool,
                               path: String,
                               query: BlockChainDB,
                               listenerQueue: DispatchQueue? = nil) -> System {
        return System (listener: listener,
                       account: account,
                       onMainnet: onMainnet,
                       path: path,
                       query: query,
                       listenerQueue: listenerQueue)
    }

    static func destroy (system: System) {
        // Stop all callbacks.  This might be inconsistent with 'deleted' events.
        System.systemRemove (index: system.index)

        // Disconnect all wallet managers
        system.disconnectAll()

        // Stop all the wallet managers.
        system.managers.forEach { $0.stop() }
    }

    ///
    /// Cease use of `system` and remove (aka 'wipe') its persistent storage.  Caution is highly
    /// warranted; none of the System's references, be they Wallet Managers, Wallets, Transfers, etc
    /// should be *touched* once the system is wiped.
    ///
    /// - Note: This function blocks until completed.  Be sure that all references are dereferenced
    ///         *before* invoking this function and remove the reference to `system` after this
    ///         returns.
    ///
    /// - Parameter system: the system to wipe
    ///
    public static func wipe (system: System) {
        // Save the path to the persistent storage
        let storagePath = system.path;

        // Destroy the system.
        destroy (system: system)

        // Clear out persistent storage
        do {
            if FileManager.default.fileExists(atPath: storagePath) {
                try FileManager.default.removeItem(atPath: storagePath)
            }
        }
        catch let error as NSError {
            print("Error: \(error.localizedDescription)")
        }
    }

    ///
    /// Remove (aka 'wipe') the persistent storage associated with any and all systems located
    /// within `atPath` except for a specified array of systems to preserve.  Generally, this
    /// function should be called on startup after all systems have been created.  When called at
    /// that time, any 'left over' systems will have their persistent storeage wiped.
    ///
    /// - Note: This function will perform no action if `atPath` does not exist or is
    ///         not a directory.
    ///
    /// - Parameter atPath: the file system path where system data is persistently stored
    /// - Parameter systems: the array of systems that shouldn not have their data wiped.
    ///
    public static func wipeAll (atPath: String, except systems: [System]) {
        do {
            try FileManager.default.contentsOfDirectory (atPath: atPath)
                .map     { (path) in atPath + "/" + path }
                .filter  { (path) in !systems.contains { path == $0.path } }
                .forEach { (path) in
                    do {
                        try FileManager.default.removeItem (atPath: path)
                    }
                    catch {}
            }
        }
        catch {}
    }
}

public enum SystemEvent {
    /// The system has been created.
    case created

    /// A network has been added to the system.  This event is generated during `configure` as
    /// each BlockChainDB blockchain is discovered.
    case networkAdded (network: Network)

    /// During `configure` once all networks have been discovered, this event is generated to
    /// mark the completion of network discovery.  The provided networks are the newly added ones;
    /// if all the known networks are required, use `system.networks`.
    case discoveredNetworks (networks: [Network])

    /// A wallet manager has been added to the system.  WalletMangers are added by the APP
    /// generally as a subset of the Networks and through a call to System.craeteWalletManager.
    case managerAdded (manager: WalletManager)
}

///
/// A SystemListener recieves asynchronous events announcing state changes to Networks, to Managers,
/// to Wallets and to Transfers.  This is an application's sole mechanism to learn of asynchronous
/// state changes.  The `SystemListener` is built upon other listeners (for WalletManager, etc) and
/// adds in `func handleSystemEvent(...)`.
///
/// All event handlers will be asynchronously performed on a listener-specific queue.  Handler will
/// be invoked as `queue.async { listener.... (...) }`.  This queue can be serial or parallel as
/// any listener calls back into System are multi-thread protected.  The queue is provided as part
/// of the System initalizer - if a queue is not specified a default one will be provided.
///
/// Note: This must be 'class bound' as System holds a 'weak' reference (for GC reasons).
///
public protocol SystemListener : /* class, */ WalletManagerListener, WalletListener, TransferListener, NetworkListener {
    ///
    /// Handle a System Event
    ///
    /// - Parameters:
    ///   - system: the system
    ///   - event: the event
    ///
    func handleSystemEvent (system: System,
                            event: SystemEvent)
}

/// A Functional Interface for a Handler
public typealias SystemEventHandler = (System, SystemEvent) -> Void

///
/// A SystemCallbackCoordinator coordinates callbacks for non-event based announcement interfaces.
///
internal final class SystemCallbackCoordinator {
    enum Handler {
        case walletFeeEstimate (Wallet.EstimateFeeHandler)
    }

    var index: Int32 = 0;
    var handlers: [Int32: Handler] = [:]

    // The queue upon which to invoke handlers.
    let queue: DispatchQueue

    public typealias Cookie = UnsafeMutableRawPointer

    var cookie: Cookie {
        return System.systemQueue.sync {
            let index = Int(self.index)
            return UnsafeMutableRawPointer (bitPattern: index)!
        }
    }

    func cookieToIndex (_ cookie: Cookie) -> Int32 {
        return 1 + Int32(UnsafeMutableRawPointer(bitPattern: 1)!.distance(to: cookie))
    }

    public func addWalletFeeEstimateHandler(_ handler: @escaping Wallet.EstimateFeeHandler) -> Cookie {
        return System.systemQueue.sync {
            index += 1
            handlers[index] = Handler.walletFeeEstimate(handler)
            // Recursively on System.systemQueue.sync
            return cookie
        }
    }

    func remWalletFeeEstimateHandler (_ cookie: UnsafeMutableRawPointer) -> Wallet.EstimateFeeHandler? {
        return System.systemQueue.sync {
            return handlers.removeValue (forKey: cookieToIndex(cookie))
                .flatMap {
                    switch $0 {
                    case .walletFeeEstimate (let handler): return handler
                    }
            }
        }
    }

    func handleWalletFeeEstimateSuccess (_ cookie: UnsafeMutableRawPointer, estimate: TransferFeeBasis) {
        if let handler = remWalletFeeEstimateHandler(cookie) {
            queue.async {
                handler (Result.success (estimate))
            }
        }
    }

    func handleWalletFeeEstimateFailure (_ cookie: UnsafeMutableRawPointer, error: Wallet.FeeEstimationError) {
        if let handler = remWalletFeeEstimateHandler(cookie) {
            queue.async {
                handler (Result.failure(error))
            }
        }
    }

    init (queue: DispatchQueue) {
        self.queue = queue
    }
}


extension System {
    internal var cryptoListener: BRCryptoCWMListener {
        // These methods are invoked direclty on a BWM, EWM, or GWM thread.
        return BRCryptoCWMListener (
            context: systemContext,

            walletManagerEventCallback: { (context, cwm, event) in
                precondition (nil != context  && nil != cwm)
                defer { cryptoWalletManagerGive(cwm) }

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { print ("SYS: Event: \(event.type): Missed {cwm}"); return }

                print ("SYS: Event: Manager (\(manager.name)): \(event.type)")

                var walletManagerEvent: WalletManagerEvent? = nil

                switch event.type {
                case CRYPTO_WALLET_MANAGER_EVENT_CREATED:
                    walletManagerEvent = WalletManagerEvent.created

                case CRYPTO_WALLET_MANAGER_EVENT_CHANGED:
                    print ("SYS: Event: Manager (\(manager.name)): \(event.type): {\(WalletManagerState (core: event.u.state.oldValue)) -> \(WalletManagerState (core: event.u.state.newValue))}")
                    walletManagerEvent = WalletManagerEvent.changed (oldState: WalletManagerState (core: event.u.state.oldValue),
                                                                     newState: WalletManagerState (core: event.u.state.newValue))

                case CRYPTO_WALLET_MANAGER_EVENT_DELETED:
                    walletManagerEvent = WalletManagerEvent.deleted

                case CRYPTO_WALLET_MANAGER_EVENT_WALLET_ADDED:
                    defer { if let wid = event.u.wallet.value { cryptoWalletGive (wid) }}
                    guard let wallet = manager.walletBy (core: event.u.wallet.value)
                        else { print ("SYS: Event: \(event.type): Missed (wallet)"); return }
                    walletManagerEvent = WalletManagerEvent.walletAdded (wallet: wallet)

                case CRYPTO_WALLET_MANAGER_EVENT_WALLET_CHANGED:
                    defer { if let wid = event.u.wallet.value { cryptoWalletGive (wid) }}
                    guard let wallet = manager.walletBy (core: event.u.wallet.value)
                        else { print ("SYS: Event: \(event.type): Missed (wallet)"); return }
                    walletManagerEvent = WalletManagerEvent.walletChanged(wallet: wallet)

                case CRYPTO_WALLET_MANAGER_EVENT_WALLET_DELETED:
                    defer { if let wid = event.u.wallet.value { cryptoWalletGive (wid) }}
                    guard let wallet = manager.walletBy (core: event.u.wallet.value)
                        else { print ("SYS: Event: \(event.type): Missed (wallet)"); return }
                    walletManagerEvent = WalletManagerEvent.walletDeleted(wallet: wallet)

                case CRYPTO_WALLET_MANAGER_EVENT_SYNC_STARTED:
                    walletManagerEvent = WalletManagerEvent.syncStarted

                case CRYPTO_WALLET_MANAGER_EVENT_SYNC_CONTINUES:
                    let timestamp: Date? = (0 == event.u.syncContinues.timestamp // CRYPTO_NO_SYNC_TIMESTAMP
                        ? nil
                        : Date (timeIntervalSince1970: TimeInterval(event.u.syncContinues.timestamp)))

                    walletManagerEvent = WalletManagerEvent.syncProgress (
                        timestamp: timestamp,
                        percentComplete: event.u.syncContinues.percentComplete)

                case CRYPTO_WALLET_MANAGER_EVENT_SYNC_STOPPED:
                    let reason = WalletManagerSyncStoppedReason(core: event.u.syncStopped.reason)
                    walletManagerEvent = WalletManagerEvent.syncEnded(reason: reason)

                case CRYPTO_WALLET_MANAGER_EVENT_SYNC_RECOMMENDED:
                    let depth = WalletManagerSyncDepth(core: event.u.syncRecommended.depth)
                    walletManagerEvent = WalletManagerEvent.syncRecommended(depth: depth)

                case CRYPTO_WALLET_MANAGER_EVENT_BLOCK_HEIGHT_UPDATED:
                    walletManagerEvent = WalletManagerEvent.blockUpdated(height: event.u.blockHeight.value)

                default: preconditionFailure()
                }

                walletManagerEvent.map { (event) in
                    system.listenerQueue.async {
                        system.listener?.handleManagerEvent (system: system,
                                                             manager: manager,
                                                             event: event)
                    }
                }
        },

            walletEventCallback: { (context, cwm, wid, event) in
                precondition (nil != context  && nil != cwm && nil != wid)
                defer { cryptoWalletManagerGive(cwm); cryptoWalletGive(wid) }

                guard let (system, manager, wallet) = System.systemExtract (context, cwm, wid)
                    else { print ("SYS: Event: \(event.type): Missed {cwm, wid}"); return }

                print ("SYS: Event: Wallet (\(wallet.name)): \(event.type)")

                var walletEvent: WalletEvent? = nil

                switch event.type {
                case CRYPTO_WALLET_EVENT_CREATED:
                    walletEvent = WalletEvent.created

                case CRYPTO_WALLET_EVENT_CHANGED:
                    walletEvent = WalletEvent.changed (oldState: WalletState (core: event.u.state.oldState),
                                                       newState: WalletState (core: event.u.state.newState))

                case CRYPTO_WALLET_EVENT_DELETED:
                    walletEvent = WalletEvent.deleted

                case CRYPTO_WALLET_EVENT_TRANSFER_ADDED:
                    defer { if let tid = event.u.transfer.value { cryptoTransferGive(tid) }}
                    guard let transfer = wallet.transferBy (core: event.u.transfer.value)
                        else { print ("SYS: Event: \(event.type): Missed (transfer)"); return }
                    walletEvent = WalletEvent.transferAdded (transfer: transfer)

                case CRYPTO_WALLET_EVENT_TRANSFER_CHANGED:
                    defer { if let tid = event.u.transfer.value { cryptoTransferGive(tid) }}
                    guard let transfer = wallet.transferBy (core: event.u.transfer.value)
                        else { print ("SYS: Event: \(event.type): Missed (transfer)"); return }
                    walletEvent = WalletEvent.transferChanged (transfer: transfer)

                case CRYPTO_WALLET_EVENT_TRANSFER_SUBMITTED:
                    defer { if let tid = event.u.transfer.value { cryptoTransferGive(tid) }}
                    guard let transfer = wallet.transferBy (core: event.u.transfer.value)
                        else { print ("SYS: Event: \(event.type): Missed (transfer)"); return }
                    walletEvent = WalletEvent.transferSubmitted (transfer: transfer, success: true)

                case CRYPTO_WALLET_EVENT_TRANSFER_DELETED:
                    defer { if let tid = event.u.transfer.value { cryptoTransferGive(tid) }}
                    guard let transfer = wallet.transferBy (core: event.u.transfer.value)
                        else { print ("SYS: Event: \(event.type): Missed (transfer)"); return }
                    walletEvent = WalletEvent.transferDeleted (transfer: transfer)

                case CRYPTO_WALLET_EVENT_BALANCE_UPDATED:
                    let amount = Amount (core: event.u.balanceUpdated.amount,
                                         take: false)
                    walletEvent = WalletEvent.balanceUpdated(amount: amount)

                case CRYPTO_WALLET_EVENT_FEE_BASIS_UPDATED:
                    let feeBasis = TransferFeeBasis (core: event.u.feeBasisUpdated.basis, take: false)
                    walletEvent = WalletEvent.feeBasisUpdated(feeBasis: feeBasis)

                case CRYPTO_WALLET_EVENT_FEE_BASIS_ESTIMATED:
                    let cookie = event.u.feeBasisEstimated.cookie!
                    if CRYPTO_SUCCESS == event.u.feeBasisEstimated.status,
                        let feeBasis = event.u.feeBasisEstimated.basis
                            .map ({ TransferFeeBasis (core: $0, take: false) }) {
                        system.callbackCoordinator.handleWalletFeeEstimateSuccess (cookie, estimate: feeBasis)
                    }
                    else {
                        let feeError = Wallet.FeeEstimationError.fromStatus(event.u.feeBasisEstimated.status)
                        system.callbackCoordinator.handleWalletFeeEstimateFailure (cookie, error: feeError)
                    }
                default: preconditionFailure()
                }

                walletEvent.map { (event) in
                    system.listenerQueue.async {
                        system.listener?.handleWalletEvent (system: manager.system,
                                                            manager: manager,
                                                            wallet: wallet,
                                                            event: event)
                    }
                }
        },

            transferEventCallback: { (context, cwm, wid, tid, event) in
                precondition (nil != context  && nil != cwm && nil != wid && nil != tid)
                defer { cryptoWalletManagerGive(cwm); cryptoWalletGive(wid); cryptoTransferGive(tid) }

                guard let (system, manager, wallet, transfer) = System.systemExtract (context, cwm, wid, tid)
                    else { print ("SYS: Event: \(event.type): Missed {cwm, wid, tid}"); return }

                print ("SYS: Event: Transfer (\(wallet.name) @ \(transfer.hash?.description ?? "pending")): \(event.type)")

                var transferEvent: TransferEvent? = nil

                switch (event.type) {
                case CRYPTO_TRANSFER_EVENT_CREATED:
                    transferEvent = TransferEvent.created

                case CRYPTO_TRANSFER_EVENT_CHANGED:
                    transferEvent = TransferEvent.changed (old: TransferState.init (core: event.u.state.old),
                                                           new: TransferState.init (core: event.u.state.new))

                case CRYPTO_TRANSFER_EVENT_DELETED:
                    transferEvent = TransferEvent.deleted

                default: preconditionFailure()
                }

                transferEvent.map { (event) in
                    system.listenerQueue.async {
                        system.listener?.handleTransferEvent (system: system,
                                                              manager: manager,
                                                              wallet: wallet,
                                                              transfer: transfer,
                                                              event: event)
                    }
                }
        })
    }
}

extension System {
    private static func cleanup (_ message: String,
                                 cwm: BRCryptoWalletManager? = nil,
                                 wid: BRCryptoWallet? = nil,
                                 tid: BRCryptoTransfer? = nil) -> Void {
        print (message)
        cwm.map { cryptoWalletManagerGive ($0) }
        wid.map { cryptoWalletGive ($0) }
        tid.map { cryptoTransferGive ($0) }
    }
}

extension System {
    internal var clientBTC: BRCryptoCWMClientBTC {
        return BRCryptoCWMClientBTC (
            funcGetBlockNumber: { (context, cwm, sid) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup("SYS: BTC: GetBlockNumber: Missed {cwm}", cwm: cwm); return }
                print ("SYS: BTC: GetBlockNumber")

                manager.query.getBlockchain (blockchainId: manager.network.uids) { (res: Result<BlockChainDB.Model.Blockchain, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve (
                        success: { cwmAnnounceGetBlockNumberSuccessAsInteger (manager.core, sid, $0.blockHeight!) },
                        failure: { (_) in cwmAnnounceGetBlockNumberFailure (manager.core, sid) })
                }},

            funcGetTransactions: { (context, cwm, sid, addresses, addressesCount, begBlockNumber, endBlockNumber) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup ("SYS: BTC: GetTransactions: Missed {cwm}", cwm: cwm); return }
                print ("SYS: BTC: GetTransactions: Blocks: {\(begBlockNumber), \(endBlockNumber)}")

                var cAddresses = addresses!
                var addresses:[String] = Array (repeating: "", count: addressesCount)
                for index in 0..<addressesCount {
                    addresses[index] = asUTF8String (cAddresses.pointee!)
                    cAddresses = cAddresses.advanced(by: 1)
                }

                manager.query.getTransactions (blockchainId: manager.network.uids,
                                               addresses: addresses,
                                               begBlockNumber: begBlockNumber,
                                               endBlockNumber: endBlockNumber,
                                               includeRaw: true) {
                                                (res: Result<[BlockChainDB.Model.Transaction], BlockChainDB.QueryError>) in
                                                defer { cryptoWalletManagerGive (cwm!) }
                                                res.resolve(
                                                    success: {
                                                        $0.forEach { (model: BlockChainDB.Model.Transaction) in
                                                            let timestamp = model.timestamp.map { $0.asUnixTimestamp } ?? 0
                                                            let height    = model.blockHeight ?? 0

                                                            if var data = model.raw {
                                                                let bytesCount = data.count
                                                                data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Void in
                                                                    let bytesAsUInt8 = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                                                                    cwmAnnounceGetTransactionsItemBTC (cwm, sid,
                                                                                                       bytesAsUInt8,
                                                                                                       bytesCount,
                                                                                                       timestamp,
                                                                                                       height)
                                                                }
                                                            }
                                                        }
                                                        cwmAnnounceGetTransactionsComplete (cwm, sid, CRYPTO_TRUE) },
                                                    failure: { (_) in cwmAnnounceGetTransactionsComplete (cwm, sid, CRYPTO_FALSE) })

                }},

            funcSubmitTransaction: { (context, cwm, sid, transactionBytes, transactionBytesLength, hashAsHex) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: BTC: SubmitTransaction: Missed {cwm}", cwm: cwm); return }
                print ("SYS: BTC: SubmitTransaction")

                let hash = asUTF8String (hashAsHex!)
                let data = Data (bytes: transactionBytes!, count: transactionBytesLength)
                manager.query.createTransaction (blockchainId: manager.network.uids, hashAsHex: hash, transaction: data) {
                    (res: Result<Void, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve(
                        success: { (_) in cwmAnnounceSubmitTransferSuccess (cwm, sid) },
                        failure: { (_) in cwmAnnounceSubmitTransferFailure (cwm, sid) })
                }
        })
    }
}

extension System {
    internal var clientETH: BRCryptoCWMClientETH {
        return BRCryptoCWMClientETH (
            funcGetEtherBalance: { (context, cwm, sid, network, address) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetEtherBalance: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network = asUTF8String (networkGetName (ewmGetNetwork (ewm)))
                let address = asUTF8String (address!)

                manager.query.getBalanceAsETH (network: network, address: address) {
                    (res: Result<String, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve (
                        success: { cwmAnnounceGetBalanceSuccess (cwm, sid, $0) },
                        failure: { (_) in cwmAnnounceGetBalanceFailure (cwm, sid) })
                }},

            funcGetTokenBalance: { (context, cwm, sid, network, address, contract) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetTokenBalance: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))
                let address  = asUTF8String (address!)
                let contract = asUTF8String (contract!)

                manager.query.getBalanceAsTOK (network: network, address: address, contract: contract) {
                    (res: Result<String, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve (
                        success: { cwmAnnounceGetBalanceSuccess (cwm, sid, $0) },
                        failure: { (_) in cwmAnnounceGetBalanceFailure (cwm, sid) })
                }},

            funcGetGasPrice: { (context, cwm, sid, network) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetGasPrice: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.getGasPriceAsETH (network: network) {
                    (res: Result<String, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve (
                        success: { cwmAnnounceGetGasPriceSuccess (cwm, sid, $0) },
                        failure: { (_) in cwmAnnounceGetGasPriceFailure (cwm, sid) })
                }},

            funcEstimateGas: { (context, cwm, sid, network, from, to, amount, price, data) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: EstimateGas: Missed {cwm}", cwm: cwm); return }

                guard let price = price.map (asUTF8String)
                    else { System.cleanup  ("SYS: ETH: EstimateGas: Missed {price}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.getGasEstimateAsETH (network: network,
                                                   from:   asUTF8String(from!),
                                                   to:     asUTF8String(to!),
                                                   amount: asUTF8String(amount!),
                                                   data:   asUTF8String(data!)) {
                                                    (res: Result<String, BlockChainDB.QueryError>) in
                                                    defer { cryptoWalletManagerGive (cwm!) }
                                                    res.resolve (
                                                        success: { cwmAnnounceGetGasEstimateSuccess (cwm, sid, $0, price) },
                                                        failure: { (_) in cwmAnnounceGetGasEstimateFailure (cwm, sid, CRYPTO_ERROR_FAILED) })
                }},

            funcSubmitTransaction: { (context, cwm, sid, network, transaction) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: SubmitTransaction: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.submitTransactionAsETH (network: network,
                                                      transaction: asUTF8String(transaction!)) {
                                                        (res: Result<String, BlockChainDB.QueryError>) in
                                                        defer { cryptoWalletManagerGive (cwm!) }
                                                        res.resolve (
                                                            success: { cwmAnnounceSubmitTransferSuccessForHash (cwm, sid, $0) },
                                                            failure: { (_) in cwmAnnounceSubmitTransferFailure (cwm, sid) })
                }},

            funcGetTransactions: { (context, cwm, sid, network, address, begBlockNumber, endBlockNumber) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetTransactions: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.getTransactionsAsETH (network: network,
                                                    address: asUTF8String (address!),
                                                    begBlockNumber: begBlockNumber,
                                                    endBlockNumber: endBlockNumber) {
                                                        (res: Result<[BlockChainDB.ETH.Transaction], BlockChainDB.QueryError>) in
                                                        defer { cryptoWalletManagerGive (cwm!) }
                                                        res.resolve(
                                                            success: { (txs: [BlockChainDB.ETH.Transaction]) in
                                                                txs.forEach { (tx: BlockChainDB.ETH.Transaction) in
                                                                    cwmAnnounceGetTransactionsItemETH (cwm, sid,
                                                                                                       tx.hash,
                                                                                                       tx.sourceAddr,
                                                                                                       tx.targetAddr,
                                                                                                       tx.contractAddr,
                                                                                                       tx.amount,
                                                                                                       tx.gasLimit,
                                                                                                       tx.gasPrice,
                                                                                                       tx.data,
                                                                                                       tx.nonce,
                                                                                                       tx.gasUsed,
                                                                                                       tx.blockNumber,
                                                                                                       tx.blockHash,
                                                                                                       tx.blockConfirmations,
                                                                                                       tx.blockTransactionIndex,
                                                                                                       tx.blockTimestamp,
                                                                                                       tx.isError)
                                                                }
                                                                cwmAnnounceGetTransactionsComplete(cwm, sid, CRYPTO_TRUE) },
                                                            failure: { (_) in cwmAnnounceGetTransactionsComplete (cwm, sid, CRYPTO_FALSE) })
                }},

            funcGetLogs: { (context, cwm, sid, network, contract, address, event, begBlockNumber, endBlockNumber) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetLogs: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.getLogsAsETH (network: network,
                                            contract: contract.map { asUTF8String($0) },
                                            address:  asUTF8String(address!),
                                            event:    asUTF8String(event!),
                                            begBlockNumber: begBlockNumber,
                                            endBlockNumber: endBlockNumber) {
                                                (res: Result<[BlockChainDB.ETH.Log], BlockChainDB.QueryError>) in
                                                defer { cryptoWalletManagerGive (cwm!) }
                                                res.resolve(
                                                    success: { (lgs: [BlockChainDB.ETH.Log]) in
                                                        lgs.forEach { (log: BlockChainDB.ETH.Log) in
                                                            let topicsCount = Int32 (log.topics.count)
                                                            var topics = log.topics.filter { !$0.isEmpty }.map { UnsafePointer<Int8>(strdup($0)) }
                                                            defer { topics.forEach { free(UnsafeMutablePointer(mutating: $0)) } }

                                                            cwmAnnounceGetLogsItem (cwm, sid,
                                                                                    log.hash,
                                                                                    log.contract,
                                                                                    topicsCount,
                                                                                    &topics,
                                                                                    log.data,
                                                                                    log.gasPrice,
                                                                                    log.gasUsed,
                                                                                    log.logIndex,
                                                                                    log.blockNumber,
                                                                                    log.blockTransactionIndex,
                                                                                    log.blockTimestamp) }
                                                        cwmAnnounceGetLogsComplete(cwm, sid, CRYPTO_TRUE) },
                                                    failure: { (_) in cwmAnnounceGetLogsComplete (cwm, sid, CRYPTO_FALSE) })
                }},

            funcGetBlocks: { (context, cwm, sid, network, address, interests, begBlockNumber, endBlockNumber) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetBlocks: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network  = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.getBlocksAsETH (network: network,
                                              address: asUTF8String(address!),
                                              interests: interests,
                                              blockStart: begBlockNumber,
                                              blockStop:  endBlockNumber) {
                                                (res: Result<[UInt64], BlockChainDB.QueryError>) in
                                                defer { cryptoWalletManagerGive (cwm!) }
                                                res.resolve (
                                                    success: {
                                                        let numbersCount = Int32 ($0.count)
                                                        var numbers = $0
                                                        numbers.withUnsafeMutableBytes {
                                                            let bytesAsUInt8 = $0.baseAddress?.assumingMemoryBound(to: UInt64.self)
                                                            cwmAnnounceGetBlocksSuccess (cwm, sid, numbersCount, bytesAsUInt8)
                                                        }},
                                                    failure: { (_) in cwmAnnounceGetBlocksFailure (cwm, sid) })
                }},

            funcGetTokens: { (context, cwm, sid) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetTokens: Missed {cwm}", cwm: cwm); return }

                manager.query.getTokensAsETH () {
                    (res: Result<[BlockChainDB.ETH.Token],BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve(
                        success: { (tokens: [BlockChainDB.ETH.Token]) in
                            tokens.forEach { (token: BlockChainDB.ETH.Token) in
                                cwmAnnounceGetTokensItem (cwm, sid,
                                                          token.address,
                                                          token.symbol,
                                                          token.name,
                                                          token.description,
                                                          token.decimals,
                                                          token.defaultGasLimit,
                                                          token.defaultGasPrice) }
                            cwmAnnounceGetTokensComplete (cwm, sid, CRYPTO_TRUE) },
                        failure: { (_) in cwmAnnounceGetTokensComplete (cwm, sid, CRYPTO_FALSE) })
                }},

            funcGetBlockNumber: { (context, cwm, sid, network) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetBlockNumber: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                manager.query.getBlockNumberAsETH (network: network) {
                    (res: Result<String, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    // If we get a successful response, but the provided blocknumber is "0" then
                    // that indicates that the JSON-RPC node is syncing.  Thus, if "0" transform
                    // to a .failure
                    res.flatMap {
                        return ($0 != "0" && $0 != "0x0"
                            ? Result.success ($0)
                            : Result.failure (BlockChainDB.QueryError.noData))
                    }.resolve (
                        success: { cwmAnnounceGetBlockNumberSuccessAsString (cwm, sid, $0) },
                        failure: { (_) in cwmAnnounceGetBlockNumberFailure (cwm, sid) })
                }},

            funcGetNonce: { (context, cwm, sid, network, address) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: ETH: GetNonce: Missed {cwm}", cwm: cwm); return }

                let ewm = cryptoWalletManagerAsETH (cwm);
                let network = asUTF8String (networkGetName (ewmGetNetwork (ewm)))

                guard let address = address.map (asUTF8String)
                    else { System.cleanup  ("SYS: ETH: GetNonce: Missed {address}", cwm: cwm); return }

                 manager.query.getNonceAsETH (network: network, address: address) {
                    (res: Result<String, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve (
                        success: { cwmAnnounceGetNonceSuccess (cwm, sid, address, $0) },
                        failure: { (_) in cwmAnnounceGetNonceFailure (cwm, sid) })
                }})
    }
}

extension System {
    internal var clientGEN: BRCryptoCWMClientGEN {
        return BRCryptoCWMClientGEN (
            funcGetBlockNumber: { (context, cwm, sid) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: GEN: GetBlockNumber: Missed {cwm}", cwm: cwm); return }
                print ("SYS: GEN: GetBlockNumber")

                manager.query.getBlockchain (blockchainId: manager.network.uids) {
                    (res: Result<BlockChainDB.Model.Blockchain, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive(cwm) }
                    res.resolve (
                        success: { cwmAnnounceGetBlockNumberSuccessAsInteger (cwm, sid, $0.blockHeight!) },
                        failure: { (_) in cwmAnnounceGetBlockNumberFailure (cwm, sid) })
                }},

            funcGetTransactions: { (context, cwm, sid, address, begBlockNumber, endBlockNumber) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: GEN: GetTransaction: Missed {cwm}", cwm: cwm); return }
                print ("SYS: GEN: GetTransactions: Blocks: {\(begBlockNumber), \(endBlockNumber)}")

                manager.query.getTransactions (blockchainId: manager.network.uids,
                                               addresses: [asUTF8String(address!)],
                                               begBlockNumber: begBlockNumber,
                                               endBlockNumber: endBlockNumber,
                                               includeRaw: true) {
                                                (res: Result<[BlockChainDB.Model.Transaction], BlockChainDB.QueryError>) in
                                                defer { cryptoWalletManagerGive(cwm) }
                                                res.resolve(
                                                    success: {
                                                        $0.forEach { (model: BlockChainDB.Model.Transaction) in
                                                            let timestamp = model.timestamp.map { $0.asUnixTimestamp } ?? 0
                                                            let height    = model.blockHeight ?? 0

                                                            if var data = model.raw {
                                                                let bytesCount = data.count
                                                                data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Void in
                                                                    let bytesAsUInt8 = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                                                                    cwmAnnounceGetTransactionsItemGEN (cwm, sid,
                                                                                                       bytesAsUInt8,
                                                                                                       bytesCount,
                                                                                                       timestamp,
                                                                                                       height)
                                                                }
                                                            }
                                                        }
                                                        cwmAnnounceGetTransactionsComplete (cwm, sid, CRYPTO_TRUE) },
                                                    failure: { (_) in cwmAnnounceGetTransactionsComplete (cwm, sid, CRYPTO_FALSE) })

                }},

            funcSubmitTransaction: { (context, cwm, sid, transactionBytes, transactionBytesLength, hashAsHex) in
                precondition (nil != context  && nil != cwm)

                guard let (system, manager) = System.systemExtract (context, cwm)
                    else { System.cleanup  ("SYS: GEN: SubmitTransaction: Missed {cwm}", cwm: cwm); return }
                print ("SYS: GEN: SubmitTransaction")

                let hash = asUTF8String (hashAsHex!)
                let data = Data (bytes: transactionBytes!, count: transactionBytesLength)
                manager.query.createTransaction (blockchainId: manager.network.uids, hashAsHex: hash, transaction: data) {
                    (res: Result<Void, BlockChainDB.QueryError>) in
                    defer { cryptoWalletManagerGive (cwm!) }
                    res.resolve(
                        success: { (_) in cwmAnnounceSubmitTransferSuccess (cwm, sid) },
                        failure: { (_) in cwmAnnounceSubmitTransferFailure (cwm, sid) })
                }
        })
    }
}

extension System {
    internal var cryptoClient: BRCryptoCWMClient {
        return BRCryptoCWMClient (context: systemContext,
                                  btc: clientBTC,
                                  eth: clientETH,
                                  gen: clientGEN)
    }
}

/// Support for Persistent Storage Migration.
///
/// Allow prior App version to migrate their SQLite database representations of BTC/BTC
/// transations, blocks and peers into 'Generic Crypto' - where these entities are persistently
/// stored in the file system (by BRFileSystem).
///
extension System {

    ///
    /// A Blob of Transaction Data
    ///
    /// - btc:
    ///
    public enum TransactionBlob {
        case btc (
            bytes: [UInt8],
            blockHeight: UInt32,
            timestamp: UInt32 // time interval since unix epoch (including '0'
        )
    }

    ///
    /// A BlockHash is 32-bytes of UInt8 data
    ///
    public typealias BlockHash = [UInt8]

    /// Validate `BlockHash`
    private static func validateBlockHash (_ hash: BlockHash) -> Bool {
        return 32 == hash.count
    }

    ///
    /// A Blob of Block Data
    ///
    /// - btc:
    ///
    public enum BlockBlob {
        case btc (
            hash: BlockHash,
            height: UInt32,
            nonce: UInt32,
            target: UInt32,
            txCount: UInt32,
            version: UInt32,
            timestamp: UInt32?,
            flags: [UInt8],
            hashes: [BlockHash],
            merkleRoot: BlockHash,
            prevBlock: BlockHash
        )
    }

    ///
    /// A Blob of Peer Data
    ///
    /// - btc:
    ///
    public enum PeerBlob {
        case btc (
            address: UInt32,  // UInt128 { .u32 = { 0, 0, 0xffff, <address> }}
            port: UInt16,
            services: UInt64,
            timestamp: UInt32?
        )
    }

    ///
    /// Migrate Errors
    ///
    enum MigrateError: Error {
        /// Migrate does not apply to this network
        case invalid

        /// Migrate couldn't access the file system
        case create

        /// Migrate failed to parse or to save a transaction
        case transaction

        /// Migrate failed to parse or to save a block
        case block

        /// Migrate failed to parse or to save a peer.
        case peer
    }

    ///
    /// Migrate the storage for a network given transaction, block and peer blobs.  The provided
    /// blobs must be consistent with `network`.  For exmaple, if `network` represents BTC or BCH
    /// then the blobs must be of type `.btc`; otherwise a MigrateError is thrown.
    ///
    /// - Parameters:
    ///   - network:
    ///   - transactionBlobs:
    ///   - blockBlobs:
    ///   - peerBlobs:
    ///
    /// - Throws: MigrateError
    ///
    public func migrateStorage (network: Network,
                                transactionBlobs: [TransactionBlob],
                                blockBlobs: [BlockBlob],
                                peerBlobs: [PeerBlob]) throws {
        guard migrateRequired (network: network)
            else { throw MigrateError.invalid }

        switch network.currency.code.lowercased() {
        case Currency.codeAsBTC,
             Currency.codeAsBCH:
            try migrateStorageAsBTC(network: network,
                                    transactionBlobs: transactionBlobs,
                                    blockBlobs: blockBlobs,
                                    peerBlobs: peerBlobs)
        default:
            throw MigrateError.invalid
        }
    }

    ///
    /// Migrate storage for BTC
    ///
    private func migrateStorageAsBTC (network: Network,
                                      transactionBlobs: [TransactionBlob],
                                      blockBlobs: [BlockBlob],
                                      peerBlobs: [PeerBlob]) throws {

        guard let migrator = cryptoWalletMigratorCreate (network.core, path)
            else { throw MigrateError.create }
        defer { cryptoWalletMigratorRelease (migrator) }

        try transactionBlobs.forEach { (blob: TransactionBlob) in
            guard case let .btc (blob) = blob
                else { throw MigrateError.transaction }

            var bytes = blob.bytes
            let status = cryptoWalletMigratorHandleTransactionAsBTC (migrator,
                                                                     &bytes, bytes.count,
                                                                     blob.blockHeight,
                                                                     blob.timestamp)
            if status.type != CRYPTO_WALLET_MIGRATOR_SUCCESS {
                throw MigrateError.transaction
            }
        }

        try blockBlobs.forEach { (blob: BlockBlob) in
            guard case let .btc (blob) = blob
                else { throw MigrateError.block }

            // On a `nil` timestamp, by definition skip out, don't migrate this blob
            guard nil != blob.timestamp
                else { return }

            guard blob.hashes.allSatisfy (System.validateBlockHash(_:)),
                System.validateBlockHash(blob.hash),
                System.validateBlockHash(blob.merkleRoot),
                System.validateBlockHash(blob.prevBlock)
                else { throw MigrateError.block }

            var flags  = blob.flags
            var hashes = blob.hashes.flatMap { $0 }  // [[UInt8 ...] ...] => [UInt8 ... ...]
            let hashesCount = blob.hashes.count

            let hash: UInt256 = blob.hash.withUnsafeBytes { $0.load (as: UInt256.self) }
            let merkleRoot: UInt256 = blob.merkleRoot.withUnsafeBytes { $0.load (as: UInt256.self) }
            let prevBlock:  UInt256 = blob.prevBlock.withUnsafeBytes  { $0.load (as: UInt256.self) }

            try hashes.withUnsafeMutableBytes { (hashesBytes: UnsafeMutableRawBufferPointer) -> Void in
                let hashesAddr = hashesBytes.baseAddress?.assumingMemoryBound(to: UInt256.self)
                let status = cryptoWalletMigratorHandleBlockAsBTC (migrator,
                                                                   hash,
                                                                   blob.height,
                                                                   blob.nonce,
                                                                   blob.target,
                                                                   blob.txCount,
                                                                   blob.version,
                                                                   blob.timestamp!,
                                                                   &flags, flags.count,
                                                                   hashesAddr, hashesCount,
                                                                   merkleRoot,
                                                                   prevBlock)
                if status.type != CRYPTO_WALLET_MIGRATOR_SUCCESS {
                    throw MigrateError.block
                }
            }
        }

        try peerBlobs.forEach { (blob: PeerBlob) in
            guard case let .btc (blob) = blob
                else { throw MigrateError.peer }

            // On a `nil` timestamp, by definition skip out, don't migrate this blob
            guard nil != blob.timestamp
                else { return }

            let status = cryptoWalletMigratorHandlePeerAsBTC (migrator,
                                                              blob.address,
                                                              blob.port,
                                                              blob.services,
                                                              blob.timestamp!)

            if status.type != CRYPTO_WALLET_MIGRATOR_SUCCESS {
                throw MigrateError.peer
            }
        }
    }

    ///
    /// If migration is required, return the currency code; otherwise, return nil.
    ///
    /// - Note: it is not an error not to migrate.
    ///
    /// - Parameter network:
    ///
    /// - Returns: The currency code or nil
    ///
    public func migrateRequired (network: Network) -> Bool {
        let code = network.currency.code.lowercased()
        return code == Currency.codeAsBTC
            || code == Currency.codeAsBCH
    }

    /// Testing

    ///
    /// Convert `transfer` to a `TransactionBlob`.
    ///
    /// - Parameter transfer:
    ///
    /// - Returns: A `TransactionBlob` or nil (if the transfer's network does not require
    ///     migration, such as for an ETH network).
    ///
    internal func asBlob (transfer: Transfer) -> TransactionBlob? {
        let network = transfer.manager.network
        guard migrateRequired(network: network)
            else { return nil }

        switch network.currency.code.lowercased() {
        case Currency.codeAsBTC,
             Currency.codeAsBCH:
            var blockHeight: UInt32 = 0
            var timestamp:   UInt32 = 0
            var bytesCount:  size_t = 0
            var bytes: UnsafeMutablePointer<UInt8>? = nil
            defer { if nil != bytes { free(bytes) }}

            cryptoTransferExtractBlobAsBTC (transfer.core,
                                            &bytes, &bytesCount,
                                            &blockHeight,
                                            &timestamp)

            return TransactionBlob.btc (bytes: UnsafeMutableBufferPointer<UInt8> (start: bytes, count: bytesCount).map { $0 },
                                        blockHeight: blockHeight,
                                        timestamp: timestamp)
        default:
            return nil
        }
    }
}

extension BRCryptoTransferEventType: CustomStringConvertible {
    public var description: String {
        switch self {
        case CRYPTO_TRANSFER_EVENT_CREATED: return "Created"
        case CRYPTO_TRANSFER_EVENT_CHANGED: return "Changed"
        case CRYPTO_TRANSFER_EVENT_DELETED: return "Deleted"
        default: return "<<unknown>>"
        }
    }
}

extension BRCryptoWalletEventType: CustomStringConvertible {
    public var description: String {
        switch self {
        case CRYPTO_WALLET_EVENT_CREATED: return "Created"
        case CRYPTO_WALLET_EVENT_CHANGED: return "Changed"
        case CRYPTO_WALLET_EVENT_DELETED: return "Deleted"

        case CRYPTO_WALLET_EVENT_TRANSFER_ADDED:     return "Transfer Added"
        case CRYPTO_WALLET_EVENT_TRANSFER_CHANGED:   return "Transfer Changed"
        case CRYPTO_WALLET_EVENT_TRANSFER_SUBMITTED: return "Transfer Submitted"
        case CRYPTO_WALLET_EVENT_TRANSFER_DELETED:   return "Transfer Deleted"

        case CRYPTO_WALLET_EVENT_BALANCE_UPDATED:   return "Balance Updated"
        case CRYPTO_WALLET_EVENT_FEE_BASIS_UPDATED: return "FeeBasis Updated"
        case CRYPTO_WALLET_EVENT_FEE_BASIS_ESTIMATED: return "FeeBasis Estimated"

        default: return "<<unknown>>"
        }
    }
}

extension BRCryptoWalletManagerEventType: CustomStringConvertible {
    public var description: String {
        switch self {
        case CRYPTO_WALLET_MANAGER_EVENT_CREATED: return "Created"
        case CRYPTO_WALLET_MANAGER_EVENT_CHANGED: return "Changed"
        case CRYPTO_WALLET_MANAGER_EVENT_DELETED: return "Deleted"

        case CRYPTO_WALLET_MANAGER_EVENT_WALLET_ADDED:   return "Wallet Added"
        case CRYPTO_WALLET_MANAGER_EVENT_WALLET_CHANGED: return "Wallet Changed"
        case CRYPTO_WALLET_MANAGER_EVENT_WALLET_DELETED: return "Wallet Deleted"

        // wallet: added, ...
        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_STARTED:   return "Sync Started"
        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_CONTINUES: return "Sync Continues"
        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_STOPPED:   return "Sync Stopped"

        case CRYPTO_WALLET_MANAGER_EVENT_BLOCK_HEIGHT_UPDATED: return "Block Height Updated"
        default: return "<<unknown>>"
        }
    }
}
