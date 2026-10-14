import Foundation

/// Every string the chat UI shows. Override some by changing a copy:
///
/// ```swift
/// var strings = HatangChatStrings.vi
/// strings.placeholder = "Hỏi chúng tôi…"
/// ```
public struct HatangChatStrings: Sendable, Hashable {
    /// Launcher label.
    public var open: String
    /// Close button label.
    public var close: String
    /// Composer placeholder.
    public var placeholder: String
    /// Send button label.
    public var send: String
    /// Header subtitle while online.
    public var online: String
    /// Header subtitle while offline.
    public var offline: String
    /// Prefix before the next opening time.
    public var backAt: String
    /// Typing indicator label.
    public var typing: String
    /// Name field placeholder.
    public var yourName: String
    /// Email field placeholder.
    public var yourEmail: String
    /// Phone field placeholder.
    public var yourPhone: String
    /// Pre-chat form submit.
    public var start: String
    /// Pre-chat form hint.
    public var leaveEmail: String
    /// Attach button label.
    public var attach: String
    /// File too large.
    public var tooLarge: String
    /// Attachment menu: camera.
    public var takePhoto: String
    /// Attachment menu: gallery.
    public var photoLibrary: String
    /// Attachment menu: files.
    public var chooseFile: String
    /// Under an attachment still uploading.
    public var uploading: String
    /// The gateway refuses the file type.
    public var unsupportedFile: String
    /// Accessibility label of a file attachment.
    public var openFile: String
    /// Failed bubble label.
    public var failed: String
    /// Retry label.
    public var retry: String
    /// The visitor's own name label.
    public var you: String
    /// Team fallback name.
    public var team: String
    /// Day separator: today.
    public var today: String
    /// Day separator: yesterday.
    public var yesterday: String
    /// Read receipt.
    public var read: String
    /// Sent receipt.
    public var sent: String
    /// Badge suffix.
    public var newMessages: String
    /// Footer.
    public var poweredBy: String
    /// Notice after an email was captured.
    public var emailSaved: String
    /// Inline email form submit.
    public var sendEmail: String
    /// Bot sender suffix.
    public var aiLabel: String
    /// Skip the optional email.
    public var skip: String
    /// Reply button (campaign teaser).
    public var reply: String
    /// CSAT thanks.
    public var rateThanks: String
    /// CSAT comment placeholder.
    public var rateComment: String
    /// CSAT submit.
    public var rateSend: String
    /// Product card: view.
    public var view: String
    /// Product card: buy.
    public var buy: String
    /// Prefilled composer text when buying.
    public var wantBuy: String
    /// Order card: total.
    public var total: String
    /// Payment card: pay.
    public var pay: String
    /// Order card: paid.
    public var paid: String
    /// Order card title.
    public var order: String
    /// Payment card: transfer note.
    public var transferNote: String
    /// Copy button.
    public var copy: String
    /// Shown after copying.
    public var copied: String
    /// Payment request past its expiry.
    public var expired: String
    /// Hint under the VietQR code.
    public var scanToPay: String
    /// Payment card without external checkout or an in-app handler.
    public var payWithTeam: String
    /// CSAT card title.
    public var ratePrompt: String
    /// Order card: shipping.
    public var shipping: String
    /// Order card: discount.
    public var discount: String
    /// Load earlier history.
    public var loadEarlier: String
    /// Connecting banner.
    public var connecting: String
    /// Offline banner.
    public var offlineBanner: String
    /// Reconnect action.
    public var reconnect: String
    /// Outdated protocol banner.
    public var updateApp: String
    /// Handoff event row.
    public var transferredToAgent: String
    /// Rate-limit notice.
    public var rateLimited: String
    /// Failed bubble hint.
    public var sendFailed: String
    /// Inbox title.
    public var inboxTitle: String
    /// Inbox empty state.
    public var noConversations: String
    /// Inbox button and closed-thread action.
    public var newConversation: String
    /// Shown instead of the composer on a closed thread.
    public var conversationClosed: String
    /// Inbox: an open or pending conversation.
    public var openStatus: String
    /// Inbox load failed.
    public var inboxError: String
    /// Resolved badge.
    public var resolved: String
    /// Unread, singular (`{count}`).
    public var unreadOne: String
    /// Unread, plural (`{count}`).
    public var unreadOther: String
    /// Permission denied notice.
    public var permissionDenied: String
    /// Notification title (`{name}`).
    public var messageFrom: String
    /// Generic error banner.
    public var errorGeneric: String
    /// Dismiss action.
    public var dismiss: String
    /// Contact button: phone.
    public var call: String
    /// Contact button: email.
    public var emailUs: String

    public init(
        open: String,
        close: String,
        placeholder: String,
        send: String,
        online: String,
        offline: String,
        backAt: String,
        typing: String,
        yourName: String,
        yourEmail: String,
        yourPhone: String,
        start: String,
        leaveEmail: String,
        attach: String,
        tooLarge: String,
        takePhoto: String,
        photoLibrary: String,
        chooseFile: String,
        uploading: String,
        unsupportedFile: String,
        openFile: String,
        failed: String,
        retry: String,
        you: String,
        team: String,
        today: String,
        yesterday: String,
        read: String,
        sent: String,
        newMessages: String,
        poweredBy: String,
        emailSaved: String,
        sendEmail: String,
        aiLabel: String,
        skip: String,
        reply: String,
        rateThanks: String,
        rateComment: String,
        rateSend: String,
        view: String,
        buy: String,
        wantBuy: String,
        total: String,
        pay: String,
        paid: String,
        order: String,
        transferNote: String,
        copy: String,
        copied: String,
        expired: String,
        scanToPay: String,
        payWithTeam: String,
        ratePrompt: String,
        shipping: String,
        discount: String,
        loadEarlier: String,
        connecting: String,
        offlineBanner: String,
        reconnect: String,
        updateApp: String,
        transferredToAgent: String,
        rateLimited: String,
        sendFailed: String,
        inboxTitle: String,
        noConversations: String,
        newConversation: String,
        conversationClosed: String,
        openStatus: String,
        inboxError: String,
        resolved: String,
        unreadOne: String,
        unreadOther: String,
        permissionDenied: String,
        messageFrom: String,
        errorGeneric: String,
        dismiss: String,
        call: String,
        emailUs: String
    ) {
        self.open = open
        self.close = close
        self.placeholder = placeholder
        self.send = send
        self.online = online
        self.offline = offline
        self.backAt = backAt
        self.typing = typing
        self.yourName = yourName
        self.yourEmail = yourEmail
        self.yourPhone = yourPhone
        self.start = start
        self.leaveEmail = leaveEmail
        self.attach = attach
        self.tooLarge = tooLarge
        self.takePhoto = takePhoto
        self.photoLibrary = photoLibrary
        self.chooseFile = chooseFile
        self.uploading = uploading
        self.unsupportedFile = unsupportedFile
        self.openFile = openFile
        self.failed = failed
        self.retry = retry
        self.you = you
        self.team = team
        self.today = today
        self.yesterday = yesterday
        self.read = read
        self.sent = sent
        self.newMessages = newMessages
        self.poweredBy = poweredBy
        self.emailSaved = emailSaved
        self.sendEmail = sendEmail
        self.aiLabel = aiLabel
        self.skip = skip
        self.reply = reply
        self.rateThanks = rateThanks
        self.rateComment = rateComment
        self.rateSend = rateSend
        self.view = view
        self.buy = buy
        self.wantBuy = wantBuy
        self.total = total
        self.pay = pay
        self.paid = paid
        self.order = order
        self.transferNote = transferNote
        self.copy = copy
        self.copied = copied
        self.expired = expired
        self.scanToPay = scanToPay
        self.payWithTeam = payWithTeam
        self.ratePrompt = ratePrompt
        self.shipping = shipping
        self.discount = discount
        self.loadEarlier = loadEarlier
        self.connecting = connecting
        self.offlineBanner = offlineBanner
        self.reconnect = reconnect
        self.updateApp = updateApp
        self.transferredToAgent = transferredToAgent
        self.rateLimited = rateLimited
        self.sendFailed = sendFailed
        self.inboxTitle = inboxTitle
        self.noConversations = noConversations
        self.newConversation = newConversation
        self.conversationClosed = conversationClosed
        self.openStatus = openStatus
        self.inboxError = inboxError
        self.resolved = resolved
        self.unreadOne = unreadOne
        self.unreadOther = unreadOther
        self.permissionDenied = permissionDenied
        self.messageFrom = messageFrom
        self.errorGeneric = errorGeneric
        self.dismiss = dismiss
        self.call = call
        self.emailUs = emailUs
    }

    /// The flat key order of `map` (plural variants under `unread_one` / `unread_other`).
    public static let keys: [String] = [
        "open",
        "close",
        "placeholder",
        "send",
        "online",
        "offline",
        "backAt",
        "typing",
        "yourName",
        "yourEmail",
        "yourPhone",
        "start",
        "leaveEmail",
        "attach",
        "tooLarge",
        "takePhoto",
        "photoLibrary",
        "chooseFile",
        "uploading",
        "unsupportedFile",
        "openFile",
        "failed",
        "retry",
        "you",
        "team",
        "today",
        "yesterday",
        "read",
        "sent",
        "newMessages",
        "poweredBy",
        "emailSaved",
        "sendEmail",
        "aiLabel",
        "skip",
        "reply",
        "rateThanks",
        "rateComment",
        "rateSend",
        "view",
        "buy",
        "wantBuy",
        "total",
        "pay",
        "paid",
        "order",
        "transferNote",
        "copy",
        "copied",
        "expired",
        "scanToPay",
        "payWithTeam",
        "ratePrompt",
        "shipping",
        "discount",
        "loadEarlier",
        "connecting",
        "offlineBanner",
        "reconnect",
        "updateApp",
        "transferredToAgent",
        "rateLimited",
        "sendFailed",
        "inboxTitle",
        "noConversations",
        "newConversation",
        "conversationClosed",
        "openStatus",
        "inboxError",
        "resolved",
        "unread_one",
        "unread_other",
        "permissionDenied",
        "messageFrom",
        "errorGeneric",
        "dismiss",
        "call",
        "emailUs",
    ]

    /// Flat map of every string (plural variants under `unread_one` / `unread_other`), for `t`.
    public var map: [String: String] {
        [
            "open": open,
            "close": close,
            "placeholder": placeholder,
            "send": send,
            "online": online,
            "offline": offline,
            "backAt": backAt,
            "typing": typing,
            "yourName": yourName,
            "yourEmail": yourEmail,
            "yourPhone": yourPhone,
            "start": start,
            "leaveEmail": leaveEmail,
            "attach": attach,
            "tooLarge": tooLarge,
            "takePhoto": takePhoto,
            "photoLibrary": photoLibrary,
            "chooseFile": chooseFile,
            "uploading": uploading,
            "unsupportedFile": unsupportedFile,
            "openFile": openFile,
            "failed": failed,
            "retry": retry,
            "you": you,
            "team": team,
            "today": today,
            "yesterday": yesterday,
            "read": read,
            "sent": sent,
            "newMessages": newMessages,
            "poweredBy": poweredBy,
            "emailSaved": emailSaved,
            "sendEmail": sendEmail,
            "aiLabel": aiLabel,
            "skip": skip,
            "reply": reply,
            "rateThanks": rateThanks,
            "rateComment": rateComment,
            "rateSend": rateSend,
            "view": view,
            "buy": buy,
            "wantBuy": wantBuy,
            "total": total,
            "pay": pay,
            "paid": paid,
            "order": order,
            "transferNote": transferNote,
            "copy": copy,
            "copied": copied,
            "expired": expired,
            "scanToPay": scanToPay,
            "payWithTeam": payWithTeam,
            "ratePrompt": ratePrompt,
            "shipping": shipping,
            "discount": discount,
            "loadEarlier": loadEarlier,
            "connecting": connecting,
            "offlineBanner": offlineBanner,
            "reconnect": reconnect,
            "updateApp": updateApp,
            "transferredToAgent": transferredToAgent,
            "rateLimited": rateLimited,
            "sendFailed": sendFailed,
            "inboxTitle": inboxTitle,
            "noConversations": noConversations,
            "newConversation": newConversation,
            "conversationClosed": conversationClosed,
            "openStatus": openStatus,
            "inboxError": inboxError,
            "resolved": resolved,
            "unread_one": unreadOne,
            "unread_other": unreadOther,
            "permissionDenied": permissionDenied,
            "messageFrom": messageFrom,
            "errorGeneric": errorGeneric,
            "dismiss": dismiss,
            "call": call,
            "emailUs": emailUs,
        ]
    }

    /// Looks up a flat `key` with `{param}` interpolation and `_one/_other` plurals when `params` has a
    /// numeric `count`.
    public func t(_ key: String, locale: HatangLocale, params: [String: any Sendable]? = nil) -> String {
        translate(map, locale: locale, key: key, params: params)
    }

    /// "3 new messages" in `locale`.
    public func unread(_ count: Int, locale: HatangLocale) -> String {
        t("unread", locale: locale, params: ["count": count])
    }

    /// The built-in strings for `locale`.
    public static func forLocale(_ locale: HatangLocale) -> HatangChatStrings {
        locale == .en ? en : vi
    }

    /// Vietnamese (product default).
    public static let vi = HatangChatStrings(
        open: "Mở trò chuyện",
        close: "Đóng",
        placeholder: "Nhập tin nhắn…",
        send: "Gửi",
        online: "Chúng tôi đang trực tuyến",
        offline: "Hiện chúng tôi vắng mặt",
        backAt: "Quay lại lúc",
        typing: "đang nhập…",
        yourName: "Tên của bạn",
        yourEmail: "Email của bạn",
        yourPhone: "Số điện thoại",
        start: "Bắt đầu",
        leaveEmail: "Để lại email để nhận trả lời",
        attach: "Đính kèm tệp",
        tooLarge: "Tệp quá lớn (tối đa 10 MB)",
        takePhoto: "Chụp ảnh",
        photoLibrary: "Thư viện ảnh",
        chooseFile: "Chọn tệp",
        uploading: "Đang tải lên…",
        unsupportedFile: "Không gửi được loại tệp này",
        openFile: "Mở tệp",
        failed: "Không gửi được",
        retry: "Thử lại",
        you: "Bạn",
        team: "Đội hỗ trợ",
        today: "Hôm nay",
        yesterday: "Hôm qua",
        read: "Đã xem",
        sent: "Đã gửi",
        newMessages: "tin nhắn mới",
        poweredBy: "Chat bởi hatang.dev",
        emailSaved: "Cảm ơn! Chúng tôi sẽ trả lời qua email.",
        sendEmail: "Gửi email",
        aiLabel: "Trợ lý AI",
        skip: "Bỏ qua",
        reply: "Trả lời",
        rateThanks: "Cảm ơn bạn đã đánh giá!",
        rateComment: "Góp ý thêm (không bắt buộc)",
        rateSend: "Gửi đánh giá",
        view: "Xem",
        buy: "Mua",
        wantBuy: "Mình muốn mua",
        total: "Tổng",
        pay: "Thanh toán",
        paid: "Đã thanh toán",
        order: "Đơn hàng",
        transferNote: "Nội dung CK",
        copy: "Sao chép",
        copied: "Đã sao chép",
        expired: "Đã hết hạn",
        scanToPay: "Quét mã QR bằng ứng dụng ngân hàng để chuyển khoản",
        payWithTeam: "Nhân viên sẽ hướng dẫn bạn hoàn tất thanh toán.",
        ratePrompt: "Bạn thấy cuộc trò chuyện thế nào?",
        shipping: "Phí ship",
        discount: "Giảm",
        loadEarlier: "Tải tin nhắn cũ hơn",
        connecting: "Đang kết nối…",
        offlineBanner: "Mất kết nối. Đang thử lại…",
        reconnect: "Kết nối lại",
        updateApp: "Vui lòng cập nhật ứng dụng để tiếp tục trò chuyện.",
        transferredToAgent: "Đã chuyển tới nhân viên hỗ trợ",
        rateLimited: "Bạn gửi hơi nhanh, đợi một chút nhé.",
        sendFailed: "Không gửi được. Chạm để thử lại.",
        inboxTitle: "Hội thoại",
        noConversations: "Chưa có hội thoại nào",
        newConversation: "Tin nhắn mới",
        conversationClosed: "Hội thoại này đã đóng.",
        openStatus: "Đang trao đổi",
        inboxError: "Không tải được danh sách. Kéo xuống để thử lại.",
        resolved: "Đã giải quyết",
        unreadOne: "{count} tin nhắn mới",
        unreadOther: "{count} tin nhắn mới",
        permissionDenied: "Ứng dụng chưa được cấp quyền",
        messageFrom: "Tin nhắn từ {name}",
        errorGeneric: "Có lỗi xảy ra. Vui lòng thử lại.",
        dismiss: "Bỏ qua",
        call: "Gọi điện",
        emailUs: "Email"
    )

    /// English.
    public static let en = HatangChatStrings(
        open: "Open chat",
        close: "Close",
        placeholder: "Type a message…",
        send: "Send",
        online: "We're online",
        offline: "We're away right now",
        backAt: "Back at",
        typing: "typing…",
        yourName: "Your name",
        yourEmail: "Your email",
        yourPhone: "Your phone",
        start: "Start",
        leaveEmail: "Leave your email to get a reply",
        attach: "Attach a file",
        tooLarge: "File is too large (max 10 MB)",
        takePhoto: "Take a photo",
        photoLibrary: "Photo library",
        chooseFile: "Choose a file",
        uploading: "Uploading…",
        unsupportedFile: "This file type can’t be sent",
        openFile: "Open file",
        failed: "Not sent",
        retry: "Retry",
        you: "You",
        team: "Support",
        today: "Today",
        yesterday: "Yesterday",
        read: "Seen",
        sent: "Sent",
        newMessages: "new messages",
        poweredBy: "Chat by hatang.dev",
        emailSaved: "Thanks! We'll reply by email.",
        sendEmail: "Send email",
        aiLabel: "AI assistant",
        skip: "Skip",
        reply: "Reply",
        rateThanks: "Thanks for your feedback!",
        rateComment: "Anything to add? (optional)",
        rateSend: "Send rating",
        view: "View",
        buy: "Buy",
        wantBuy: "I'd like to buy",
        total: "Total",
        pay: "Pay now",
        paid: "Paid",
        order: "Order",
        transferNote: "Transfer note",
        copy: "Copy",
        copied: "Copied",
        expired: "Expired",
        scanToPay: "Scan the QR code with your banking app to pay",
        payWithTeam: "The team will tell you how to complete this payment.",
        ratePrompt: "How was your conversation?",
        shipping: "Shipping",
        discount: "Discount",
        loadEarlier: "Load earlier messages",
        connecting: "Connecting…",
        offlineBanner: "Connection lost. Retrying…",
        reconnect: "Reconnect",
        updateApp: "Please update the app to keep chatting.",
        transferredToAgent: "Transferred to a human agent",
        rateLimited: "You're sending too quickly, give it a moment.",
        sendFailed: "Not sent. Tap to retry.",
        inboxTitle: "Conversations",
        noConversations: "No conversations yet",
        newConversation: "New message",
        conversationClosed: "This conversation is closed.",
        openStatus: "Ongoing",
        inboxError: "Could not load your conversations. Pull to retry.",
        resolved: "Resolved",
        unreadOne: "{count} new message",
        unreadOther: "{count} new messages",
        permissionDenied: "The app was not granted permission",
        messageFrom: "Message from {name}",
        errorGeneric: "Something went wrong. Please try again.",
        dismiss: "Dismiss",
        call: "Call us",
        emailUs: "Email"
    )

}
