import UIKit

class MessageVC: AbstractViewController, UITableViewDelegate, UIAlertViewDelegate, APIManagerDelegate, AccountsChousePopUpDelegate, DetailedTableViewCellDelegate
{
    private struct DefinedCell
    {
        var type :ConversationCellType = ConversationCellType.Unknown
        var height :CGFloat = 44
        var minCosignatories :Int? = nil
        var detailsTop :NSAttributedString = NSAttributedString(string: "")
        var detailsMiddle :NSAttributedString = NSAttributedString(string: "")
        var detailsBottom :NSAttributedString = NSAttributedString(string: "")
    }
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var userInfo: NEMLabel!
    @IBOutlet weak var amoundField: NEMTextField!
    @IBOutlet weak var messageField: NEMTextField!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var accountsButton: UIButton!
    @IBOutlet weak var amoundContainerView: UIView!
    @IBOutlet weak var contactInfo: UILabel!
    
    @IBOutlet weak var encButton: UIButton!
    
    private var _unconfirmedTransactions  :[TransactionPostMetaData] = []
    private var _transactions :[TransactionPostMetaData] = []
    private var _definedCells :[DefinedCell] = []

    private var _apiManager :APIManager = APIManager()
    private var _operationDipatchQueue :dispatch_queue_t = dispatch_queue_create("Message VC operation queu", nil)
    
    private let _contact :Correspondent = State.currentContact!
    private var _accounts :[AccountGetMetaData] = []
    private var _mainAccount :AccountGetMetaData? = nil
    private var _activeAccount :AccountGetMetaData? = nil
    
    private var _isEnc = false
    
    private var _canShowKeyboard = true
    
    let contact :Correspondent = State.currentContact!
    
    private let rowLength :Int = 21
    private let textSizeCommon :CGFloat = 12
    private let textSizeXEM :CGFloat = 14
    
    private let greenColor :UIColor = UIColor(red: 65/256, green: 206/256, blue: 123/256, alpha: 1)
    private let grayColor :UIColor = UIColor(red: 239 / 255, green: 239 / 255, blue: 244 / 255, alpha: 1)
    
    // MARK: - Load Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        State.fromVC = SegueToMessageVC
        State.currentVC = SegueToMessageVC
        
        _apiManager.delegate = self
        
        _initButtonsConfigs()
        contactInfo.text = contact.name
        
        let privateKey = HashManager.AES256Decrypt(State.currentWallet!.privateKey, key: State.currentWallet!.password)
        let account_address = AddressGenerator.generateAddressFromPrivateKey(privateKey!)
        
        if !Validate.stringNotEmpty(self.contact.public_key){
            self._apiManager.accountGet(State.currentServer!, account_address: self.contact.address)
        }
        
        _apiManager.accountGet(State.currentServer!, account_address: account_address)
        
        self.tableView.tableFooterView = UIView(frame: CGRectZero)
        scrollToEnd()
        
        let observer: NSNotificationCenter = NSNotificationCenter.defaultCenter()
        
        observer.addObserver(self, selector: "keyboardWillShow:", name: UIKeyboardWillShowNotification, object: nil)
        observer.addObserver(self, selector: "keyboardWillHide:", name: UIKeyboardWillHideNotification, object: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - IBAction
    
    @IBAction func backButtonTouchUpInside(sender: AnyObject) {
        if self.delegate != nil && self.delegate!.respondsToSelector("pageSelected:") {
            (self.delegate as! MainVCDelegate).pageSelected(SegueToLoginVC)
        }
    }
    
    @IBAction func amoundFieldDidEndOnExit(sender: UITextField) {
        if Double(sender.text!) == nil {
            sender.text = "0"
        }
    }
    
    @IBAction func messageFieldDidEndOnExit(sender: UITextField) {

    }
    
    @IBAction func copyCorrespondentAddress(sender: AnyObject) {
        
        let pasteBoard :UIPasteboard = UIPasteboard.generalPasteboard()
        pasteBoard.string = _contact.address
    }
    
    @IBAction func encTouchUpInside(sender: UIButton) {
        _isEnc = !_isEnc
        sender.backgroundColor = (_isEnc) ? greenColor : grayColor
    }
    
    @IBAction func accountsButtonDidTouchInside(sender: AnyObject){
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let accounts :AccountsChousePopUp =  storyboard.instantiateViewControllerWithIdentifier("AccountsChousePopUp") as! AccountsChousePopUp
        
        accounts.view.frame = CGRect(x: tableView.frame.origin.x + 10,
            y:  tableView.frame.origin.y + 10,
            width: tableView.frame.width - 20,
            height: tableView.frame.height - 11)
        
        accounts.view.layer.opacity = 0
        accounts.delegate = self
        
        var wallets = _mainAccount?.cosignatoryOf ?? []
        if _mainAccount != nil
        {
            wallets.append(self._mainAccount!)
        }
        accounts.wallets = wallets
        
        if accounts.wallets.count > 0
        {
            self.view.addSubview(accounts.view)
            
            UIView.animateWithDuration(0.5, animations: { () -> Void in
                accounts.view.layer.opacity = 1
                }, completion: nil)
        }
        
    }
    
    @IBAction func sendButtonTouchUpInside(sender: AnyObject) {
        
        if _activeAccount == nil || State.currentServer == nil {
            return
        }
        
        let transaction :TransferTransaction = TransferTransaction()
        
        if let amount = Double(amoundField.text!) {
            if Double(_activeAccount?.balance ?? -1) > amount {
                transaction.amount = amount
            } else {
                let alert :UIAlertController = UIAlertController(title: NSLocalizedString("INFO", comment: "Title"), message: NSLocalizedString("ACCOUNT_NOT_ENOUGHT_MONEY", comment: "Description") , preferredStyle: UIAlertControllerStyle.Alert)
                
                let ok :UIAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Destructive) {
                    alertAction -> Void in
                }
                
                alert.addAction(ok)
                self.presentViewController(alert, animated: true, completion: nil)
                
                return
            }
        } else {
            amoundField.text = "0"
            transaction.amount = 0
            return
        }
                
        let messageTextHex = messageField.text!.hexadecimalStringUsingEncoding(NSUTF8StringEncoding)
        
        if !Validate.hexString(messageTextHex!) {
            let alert :UIAlertController = UIAlertController(title: NSLocalizedString("INFO", comment: "INFO"), message: NSLocalizedString("NOT_A_HEX_STRING", comment: "Error: NOT_A_HEX_STRING") , preferredStyle: UIAlertControllerStyle.Alert)
            
            let ok :UIAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Destructive) {
                alertAction -> Void in
            }
            
            alert.addAction(ok)
            self.presentViewController(alert, animated: true, completion: nil)
            
            return
        }
        
        var messageBytes :[UInt8] = messageTextHex!.asByteArray()

        
        if _isEnc
        {
            guard let contactPublicKey = contact.public_key else {
                let alert :UIAlertController = UIAlertController(title: NSLocalizedString("INFO", comment: "INFO"), message: NSLocalizedString("NO_PUBLIC_KEY_FOR_ENC", comment: "Error: NO_PUBLIC_KEY_FOR_ENC") , preferredStyle: UIAlertControllerStyle.Alert)
                
                let ok :UIAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Destructive) {
                    alertAction -> Void in
                }
                
                alert.addAction(ok)
                self.presentViewController(alert, animated: true, completion: nil)
                
                return

            }
            var encryptedMessage :[UInt8] = Array(count: 32, repeatedValue: 0)
            encryptedMessage = MessageCrypto.encrypt(messageBytes, senderPrivateKey: HashManager.AES256Decrypt(State.currentWallet!.privateKey, key: State.currentWallet!.password)!, recipientPublicKey: contactPublicKey)
            messageBytes = encryptedMessage
        }
        
        transaction.message.payload = messageBytes
        transaction.message.type = (_isEnc) ? MessageType.Ecrypted.rawValue : MessageType.Normal.rawValue
        
        var fee = 0
        
        if transaction.amount >= 8 {
            fee = Int(max(2, 99 * atan(transaction.amount / 150000)))
        }
        else {
            fee = 10 - Int(transaction.amount)
        }
        
        if messageField.text!.utf16.count != 0 {
            fee += Int(2 * max(1, Int( transaction.message.payload!.count / 16)))
        }
        
        transaction.timeStamp = Double(Int(TimeSynchronizator.nemTime))
        transaction.fee = Double(fee)
        transaction.recipient = contact.address
        transaction.type = transferTransaction
        transaction.deadline = Double(Int(TimeSynchronizator.nemTime + waitTime))
        transaction.version = 1
        transaction.signer = _activeAccount?.publicKey
        
        _apiManager.prepareAnnounce(State.currentServer!, transaction: transaction)
        
        messageField.text = ""
        amoundField.text = ""
    }
    
    final func defineData() {
        let publicKey :String = KeyGenerator.generatePublicKey(HashManager.AES256Decrypt(State.currentWallet!.privateKey, key: State.currentWallet!.password)!)
        var data :[DefinedCell] = []
        
        for transaction in _transactions {
            var definedCell : DefinedCell = DefinedCell()
            definedCell.type = .Incoming
            
            if (transaction.signer == publicKey) {
                definedCell.type = .Outgoing
            }
            
            for cosignatory in _activeAccount!.cosignatories {
                if cosignatory.publicKey == transaction.signer {
                    definedCell.type = .Outgoing
                    break
                }
            }
            
            for cosignatory in _activeAccount!.cosignatoryOf {
                if cosignatory.publicKey == transaction.signer {
                    definedCell.type = .Outgoing
                    break
                }
            }
            
            let innertTransaction = (transaction.type == multisigTransaction) ? ((transaction as! MultisigTransaction).innerTransaction as! TransferTransaction) :
            (transaction as! TransferTransaction)
            innertTransaction.message.signer = contact.public_key
            var message :NSMutableAttributedString = NSMutableAttributedString(string: innertTransaction.message.getMessageString() ?? "Could not decrypt" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue-Light", size: textSizeCommon)!])
            
            if(innertTransaction.amount > 0) {
                var text :String = "\(innertTransaction.amount / 1000000) XEM"
                if message != ""
                {
                    text = "\n" + text
                }
                
                let messageXEMS :NSMutableAttributedString = NSMutableAttributedString(string:text , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: textSizeXEM)! ])
                message.appendAttributedString(messageXEMS)
            }
            
            message = (message.length == 0) ? NSMutableAttributedString(string:NSLocalizedString("EMPTY_MESSAGE", comment: "Description") , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue-Italic", size: textSizeCommon)! ]) : message
            
            definedCell.height = _heightForCell(message, width: tableView.frame.width - 120) + 20

            message = NSMutableAttributedString(string:"Block: " , attributes: nil)
            message.appendAttributedString(NSMutableAttributedString(string:"\(innertTransaction.height)" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 10)! ]))
            definedCell.detailsTop = message
            
            message = NSMutableAttributedString(string:"Fee: " , attributes: nil)
            message.appendAttributedString(NSMutableAttributedString(string:"\(innertTransaction.fee / 1000000)" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 10)! ]))
            
            definedCell.detailsMiddle = message
            
            data.append(definedCell)
        }
        
        for transaction in _unconfirmedTransactions {
            var definedCell : DefinedCell = DefinedCell()
            definedCell.type = .Processing
            
            let innertTransaction = (transaction.type == multisigTransaction) ? ((transaction as! MultisigTransaction).innerTransaction as! TransferTransaction) :
                (transaction as! TransferTransaction)
            innertTransaction.message.signer = contact.public_key

            var message :NSMutableAttributedString = NSMutableAttributedString(string: innertTransaction.message.getMessageString() ?? "Could not decrypt" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue-Light", size: textSizeCommon)!])
            
            if(innertTransaction.amount != 0) {
                var text :String = "\(innertTransaction.amount / 1000000) XEM"
                if message != ""
                {
                    text = "\n" + text
                }
                
                let messageXEMS :NSMutableAttributedString = NSMutableAttributedString(string:text , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: textSizeXEM)! ])
                message.appendAttributedString(messageXEMS)
            }
            
            message = (message.length == 0) ? NSMutableAttributedString(string:NSLocalizedString("EMPTY_MESSAGE", comment: "Description") , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue-Italic", size: textSizeCommon)! ]) : message
            
            definedCell.height =  max(_heightForCell(message, width: tableView.frame.width - 120), CGFloat(80))
            
            
            if transaction.type == multisigTransaction {
                definedCell.minCosignatories = _getMinCosigFor(transaction as! MultisigTransaction)
            }
            
            if transaction.type == multisigTransaction {
                let signerAdress = AddressGenerator.generateAddress(innertTransaction.signer)
                let singnaturesCount = (transaction as! MultisigTransaction).signatures.count
                var cosignatories = 0
                var minCosig = 0

                for account in _accounts {
                    if account.address == signerAdress {
                        minCosig = account.minCosignatories!
                        cosignatories = account.cosignatories.count
                        break
                    }
                }
                let attribute = [NSForegroundColorAttributeName : greenColor]

                message = NSMutableAttributedString(string:"\(singnaturesCount)" , attributes: attribute)
                message.appendAttributedString(NSMutableAttributedString(string:" of " , attributes: nil))
                message.appendAttributedString(NSMutableAttributedString(string:"\(cosignatories)" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 10)! ]))
                message.appendAttributedString(NSMutableAttributedString(string:" XEM" , attributes: nil))
                
                definedCell.detailsTop = message
                
                message = NSMutableAttributedString(string:"Min " , attributes: nil)
                message.appendAttributedString(NSMutableAttributedString(string:"\(((minCosig == 0) ? cosignatories : minCosig))" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 10)! ]))
                message.appendAttributedString(NSMutableAttributedString(string:" Signers" , attributes: nil))
                
                definedCell.detailsMiddle = message
                
                message = NSMutableAttributedString(string:"Fee: " , attributes: nil)
                message.appendAttributedString(NSMutableAttributedString(string:"\(innertTransaction.fee / 1000000)" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 10)! ]))
                
                definedCell.detailsBottom = message
            } else {
                message = NSMutableAttributedString(string:"Fee: " , attributes: nil)
                message.appendAttributedString(NSMutableAttributedString(string:"\(innertTransaction.fee / 1000000)" , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 10)! ]))
                
                definedCell.detailsMiddle = message
            }
            
            data.append(definedCell)
        }
        _definedCells = data
    }
    
    func scrollToEnd() {
        var indexPath :NSIndexPath!
        
        if (tableView.numberOfRowsInSection(0) != 0) {
            indexPath = NSIndexPath(forRow: tableView.numberOfRowsInSection(0) - 1 , inSection: 0)
        }
        
        if indexPath != nil {
            tableView.scrollToRowAtIndexPath(indexPath, atScrollPosition: UITableViewScrollPosition.Bottom, animated: true)
        }
    }
    
    // MARK: - TableView Delegate
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if _definedCells.count > 0 {
            var count = _transactions.count + 1
            count += (_unconfirmedTransactions.count > 0) ? _unconfirmedTransactions.count + 1 : 0
            return count
        }
        
        return 0
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        if( !(indexPath.row == 0) ) {
            var index :Int = 0
            let cell : ConversationTableViewCell = self.tableView.dequeueReusableCellWithIdentifier("messageCell") as! ConversationTableViewCell
            cell.detailDelegate = self
            var transaction :TransactionPostMetaData!
            var innertTransaction :TransferTransaction!

            if indexPath.row <= _transactions.count {
                index = indexPath.row - 1
                cell.cellType = _definedCells[indexPath.row - 1].type
                cell.setDetails(_definedCells[indexPath.row - 1].detailsTop, middle: _definedCells[indexPath.row - 1].detailsMiddle, bottom: _definedCells[indexPath.row - 1].detailsBottom)
                transaction = _transactions[index]
                innertTransaction = (transaction.type == multisigTransaction) ? ((transaction as! MultisigTransaction).innerTransaction as! TransferTransaction) :
                    (transaction as! TransferTransaction)
            } else {
                
                index = indexPath.row - _transactions.count - 2
                
                if index < 0 {
                    let headerCell :UITableViewCell  = self.tableView.dequeueReusableCellWithIdentifier("groupHeader")!
                    return headerCell
                }
                cell.cellType = _definedCells[indexPath.row - 2].type
                cell.setDetails(_definedCells[indexPath.row - 2].detailsTop, middle: _definedCells[indexPath.row - 2].detailsMiddle, bottom: _definedCells[indexPath.row - 2].detailsBottom)
                transaction  = _unconfirmedTransactions[index]
                innertTransaction = (transaction.type == multisigTransaction) ? ((transaction as! MultisigTransaction).innerTransaction as! TransferTransaction) :
                    (transaction as! TransferTransaction)
            }
            innertTransaction.message.signer = contact.public_key
            let messageText = innertTransaction.message.getMessageString() ?? "Could not decrypt"
            
            var message :NSMutableAttributedString = NSMutableAttributedString(string: messageText , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue-Light", size: textSizeCommon)!])
            
            if(innertTransaction.amount > 0) {
                var text :String = "\(innertTransaction.amount / 1000000) XEM"
                if messageText != ""
                {
                    text = "\n" + text
                }
                
                let messageXEMS :NSMutableAttributedString = NSMutableAttributedString(string:text , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: textSizeXEM)! ])
                message.appendAttributedString(messageXEMS)
            }
            
            message = (message.length == 0) ? NSMutableAttributedString(string:NSLocalizedString("EMPTY_MESSAGE", comment: "Description") , attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue-Italic", size: textSizeCommon)! ]) : message
            cell.setMessage(message)
            let dateFormatter = NSDateFormatter()
            dateFormatter.dateFormat = "HH:mm dd.MM.yy "
            
            let timeStamp = Double(innertTransaction.timeStamp)
            
            cell.setDate(dateFormatter.stringFromDate(NSDate(timeIntervalSince1970: genesis_block_time + timeStamp)))
            
            if(indexPath.row == _transactions.count ) {
                scrollToEnd()
            }
            return cell
        }
        
        let cell :UITableViewCell  = self.tableView.dequeueReusableCellWithIdentifier("simpl")!
        return cell
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        if indexPath.row == 0 {
            var height :CGFloat = 0
            
            for cell in _definedCells {
                height += cell.height
            }
            
            if height >= self.tableView.bounds.height {
                return 1
            }
            else {
                return self.tableView.bounds.height - height
            }
        } else if indexPath.row <= _transactions.count + 1  {
            
            return _definedCells[indexPath.row - 1].height
        } else if indexPath.row == _transactions.count + 1 {
            return 44
        } else {
            return _definedCells[indexPath.row - 2].height
        }
    }
    
    //MARK: - DetailedTableViewCellDelegate Methods
    
    func showDetailsForCell(cell: DetailedTableViewCell) {
        cell.detailsIsShown = true
    }
    
    func hideDetailsForCell(cell: DetailedTableViewCell) {
        cell.detailsIsShown = false
    }
    
    // MARK: - APIManagerDelegate Methods
    
    final func accountGetResponceWithAccount(account: AccountGetMetaData?) {
        dispatch_async(_operationDipatchQueue, {
            () -> Void in
            if let responceAccount = account {
                
                if responceAccount.publicKey == nil {
                    let privateKey = HashManager.AES256Decrypt(State.currentWallet!.privateKey, key: State.currentWallet!.password)
                    let account_address = AddressGenerator.generateAddressFromPrivateKey(privateKey!)
                    
                    if account_address == responceAccount.address {
                        responceAccount.publicKey = KeyGenerator.generatePublicKey(privateKey!)
                    }
                }
                
                if !Validate.stringNotEmpty(self.contact.public_key) && self.contact.address == responceAccount.address {
                    self.contact.public_key = responceAccount.publicKey
                    return
                }
                
                if  self._activeAccount == nil {
                    self._activeAccount = responceAccount
                }
                
                if self._mainAccount == nil {
                    
                    self._mainAccount = responceAccount
                    self._accounts.append(self._mainAccount!)
                    
                    for multisigAccount in responceAccount.cosignatoryOf {
                        self._apiManager.accountGet(State.currentServer!, account_address: multisigAccount.address)
                    }
                    
                    self._refreshHistory()
                } else {
                    if self._accounts.count < self._mainAccount!.cosignatoryOf.count {
                        self._accounts.append(responceAccount)
                    }
                }
                
                dispatch_async(dispatch_get_main_queue() , {
                    () -> Void in
                    var userDescription :NSMutableAttributedString!
                    
                    if let wallet = State.currentWallet {
                        userDescription = NSMutableAttributedString(string: "\(wallet.login)")
                    }
                    
                    let attribute = [NSForegroundColorAttributeName : UIColor(red: 65/256, green: 206/256, blue: 123/256, alpha: 1)]
                    let balance = " \(self._activeAccount!.balance / 1000000) XEM"
                    
                    userDescription.appendAttributedString(NSMutableAttributedString(string: balance, attributes: attribute))
                    
                    self.userInfo.attributedText = userDescription
                })
                
            } else {
                dispatch_async(dispatch_get_main_queue() , {
                    () -> Void in
                    self.userInfo.attributedText = NSMutableAttributedString(string: NSLocalizedString("LOST_CONNECTION", comment: "Title"), attributes: [NSForegroundColorAttributeName : UIColor.redColor()])
                })
            }
        })
    }
    
    final func accountTransfersAllResponceWithTransactions(data: [TransactionPostMetaData]?) {
        dispatch_async(_operationDipatchQueue, {
            () -> Void in
            if let data = data {
                
                self._transactions = self._findMessages(data)
                
                self._sortMessages()
                self.defineData()
                
                dispatch_async(dispatch_get_main_queue() , {
                    () -> Void in
                    self.tableView.reloadData()
                    self.scrollToEnd()
                })
                
            } else {
                dispatch_async(dispatch_get_main_queue() , {
                    () -> Void in
                    self.userInfo.attributedText = NSMutableAttributedString(string: NSLocalizedString("LOST_CONNECTION", comment: "Title"), attributes: [NSForegroundColorAttributeName : UIColor.redColor()])
                })
            }
        })
    }
    
    final func unconfirmedTransactionsResponceWithTransactions(data: [TransactionPostMetaData]?) {
        dispatch_async(_operationDipatchQueue, {
            () -> Void in
            
            if let data = data {
    
                self._unconfirmedTransactions = self._findMessages(data).reverse()
                self.defineData()
                
                dispatch_async(dispatch_get_main_queue() , {
                    () -> Void in
                    self.tableView.reloadData()
                    self.scrollToEnd()
                })
            } else {
                dispatch_async(dispatch_get_main_queue() , {
                    () -> Void in
                    self.userInfo.attributedText = NSMutableAttributedString(string: NSLocalizedString("LOST_CONNECTION", comment: "Title"), attributes: [NSForegroundColorAttributeName : UIColor.redColor()])
                })
            }
        })
    }
    
    func prepareAnnounceResponceWithTransactions(data: [TransactionPostMetaData]?) {
        if !(data ?? []).isEmpty {
            self._refreshHistory()
            let alert :UIAlertController = UIAlertController(title: NSLocalizedString("INFO", comment: "Title"), message:  NSLocalizedString("TRANSACTION_ANOUNCE_SUCCESS", comment: "Description"), preferredStyle: UIAlertControllerStyle.Alert)
            
            let ok :UIAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default) {
                alertAction -> Void in
            }
            
            alert.addAction(ok)
            self.presentViewController(alert, animated: true, completion: nil)
            
        } else {
            let alert :UIAlertController = UIAlertController(title: NSLocalizedString("INFO", comment: "Title"), message: NSLocalizedString("TRANSACTION_ANOUNCE_FAILED", comment: "Description"), preferredStyle: UIAlertControllerStyle.Alert)
            
            let ok :UIAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default) {
                alertAction -> Void in
            }
            
            alert.addAction(ok)
            self.presentViewController(alert, animated: true, completion: nil)
        }
    }
    
    //MARK: - AccountsChousePopUpDelegate Methods
    
    func didChouseAccount(account: AccountGetMetaData) {
        _activeAccount = account
        
        let userDescription :NSMutableAttributedString = NSMutableAttributedString(string: "\(_activeAccount!.address.nemName())")
        
        let attribute = [NSForegroundColorAttributeName : UIColor(red: 65/256, green: 206/256, blue: 123/256, alpha: 1)]
        let balance = " \(self._activeAccount!.balance / 1000000) XEM"
        
        userDescription.appendAttributedString(NSMutableAttributedString(string: balance, attributes: attribute))
        
        dispatch_async(dispatch_get_main_queue() , {
            () -> Void in
            self.userInfo.attributedText = userDescription
        })
    }
    
    //MARK: - Private Helpers
    
    private func _heightForCell(message: NSMutableAttributedString, width: CGFloat)-> CGFloat {
        let label:MessageUILabel = MessageUILabel(frame: CGRectMake(0, 0, width, CGFloat.max))
        label.numberOfLines = 10
        label.lineBreakMode = NSLineBreakMode.ByWordWrapping
        label.attributedText = message
        
        label.sizeToFit()
        return label.frame.height
    }
    
    private func _initButtonsConfigs() {
        if accountsButton != nil {
            accountsButton.layer.cornerRadius = 5
        }
        
        if sendButton != nil {
            sendButton.layer.cornerRadius = 5
        }
        
        if amoundContainerView != nil {
            amoundContainerView.layer.cornerRadius = 5
            amoundContainerView.clipsToBounds = true
        }
        
        if messageField != nil {
            messageField.layer.cornerRadius = 5
        }
    }
    
    private func _findMessages(data: [TransactionPostMetaData]) -> [TransactionPostMetaData] {
        var _transactions :[TransactionPostMetaData] = data
        
        for var index = 0; index < _transactions.count; index++ {
            var needToSave = false
            var recipient = ""
            
            if _transactions[index].type == transferTransaction {
                recipient = (_transactions[index] as! TransferTransaction).recipient
            } else if _transactions[index].type == multisigTransaction {
                let innerTransaction = (_transactions[index] as! MultisigTransaction).innerTransaction
                if innerTransaction.type == transferTransaction {
                    recipient = (innerTransaction as! TransferTransaction).recipient
                }
            }
            
            if AddressGenerator.generateAddress(_transactions[index].signer) == self._mainAccount!.address && recipient == self.contact.address {
                needToSave = true
            }
            
            if AddressGenerator.generateAddress(_transactions[index].signer) == self.contact.address && recipient == self._mainAccount!.address {
                needToSave = true
            }
            
            if !needToSave {
                _transactions.removeAtIndex(index)
                index--
            }
        }
        
        return _transactions
    }
    
    private final func _refreshHistory() {
        self._apiManager.unconfirmedTransactions(State.currentServer!, account_address: self._mainAccount!.address)
        
        if self._activeAccount!.cosignatoryOf.count > 0 {
            
            for cosignatory in self._activeAccount!.cosignatoryOf {
                self._apiManager.unconfirmedTransactions(State.currentServer!, account_address: cosignatory.address)
            }
        }
        
        self._apiManager.accountTransfersAll(State.currentServer!, account_address: self._mainAccount!.address)
    }
    
    private final func _getMinCosigFor(transaction: MultisigTransaction) -> Int? {
        let innertTransaction =  (transaction.innerTransaction as! TransferTransaction)
        let transactionsignerAddress = AddressGenerator.generateAddress(innertTransaction.signer)
        
        for account in _accounts {
            if account.address == transactionsignerAddress {
                return account.minCosignatories
            }
        }
        
        return nil
    }
    
    func _sortMessages() {
        var accum :TransactionPostMetaData!
        for(var index = 0; index < _transactions.count; index++) {
            var sorted = true
            
            for(var index = 0; index < _transactions.count - 1; index++) {
                
                let valueA :Double = Double(_transactions[index].id)
                
                let valueB :Double = Double(_transactions[index + 1].id)
                
                if valueA > valueB {
                    sorted = false
                    accum = _transactions[index]
                    _transactions[index] = _transactions[index + 1]
                    _transactions[index + 1] = accum
                }
            }
            
            if sorted {
                break
            }
        }
    }
    
    //MARK: - Keyboard Methods
    
    func keyboardWillShow(notification: NSNotification) {
        if _canShowKeyboard {
            let info:NSDictionary = notification.userInfo!
            let keyboardSize = (info[UIKeyboardFrameEndUserInfoKey] as! NSValue).CGRectValue()
            
            let height:CGFloat = keyboardSize.height - 65
            
            UIView.animateWithDuration(0.25, animations: { () -> Void in
                self.view.frame.size.height = self.view.frame.height - height
                }, completion: { (success) -> Void in
                    self.scrollToEnd()

            })
            _canShowKeyboard = false
        }
    }
    
    func keyboardWillHide(notification: NSNotification) {
        
        if !_canShowKeyboard {
            let info:NSDictionary = notification.userInfo!
            let keyboardSize = (info[UIKeyboardFrameEndUserInfoKey] as! NSValue).CGRectValue()
            
            let height:CGFloat = keyboardSize.height - 65
            
            UIView.animateWithDuration(0.25, animations: { () -> Void in
                self.view.frame.size.height = self.view.frame.height + height
                }, completion: { (success) -> Void in
                    self.scrollToEnd()
                    
            })
            
            _canShowKeyboard = true
        }
    }
}
