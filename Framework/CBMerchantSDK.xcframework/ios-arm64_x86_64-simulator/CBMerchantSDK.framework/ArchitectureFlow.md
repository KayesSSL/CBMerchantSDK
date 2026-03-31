# CashBaba iOS SDK (CBSDKSwiftCodes) Architecture and Flows

## Overview
- Module provides a UIKit-based SDK mirroring Android SDK flows (PIN management, transactions, CPQRC, Prepaid Card).
- Layers:
  - Facade: `CashBabaSDK`
  - Presenter/Coordinator: `SDKPresenter`, `MainCoordinator`, `Routes`
  - Networking: `APIHandler`, `WebServiceHandler`, `ApiPaths`, `Config`, `Encryptor`
  - Repository: `CashBabaRepository`, `CashBabaRepositoryImpl`
  - Models: Codable models in `Models.swift`
  - Utilities: `SDKError`, `SessionTimerManager`, `CBSDKDataStorage` (Android DataStorage parity), `CBSDKManager`, UI helpers
  - UI Modules: Splash, PIN Setup, Change PIN, Forget PIN, OTP Verification, Welcome/TnC, Confirm PIN

## Facade (`Init/CashBabaSDK.swift`)
- Public entry for API calls and config.
- Initialization:
  - `initialize(environment:languageCode:scope:wToken:pemData:)`
  - Convenience: `initialize(... pemResourceName:in:)` loads PEM from bundle.
- Callbacks channel (Android CurrentFlow equivalent):
  - `onSuccess(OnSuccessModel)`, `onFailed(OnFailedModel)`, `onUserCancel()` set via `setCallbacks(...)`.
- Token handling:
  - On `clientVerification`, stores token and starts `SessionTimerManager` with `expiresIn`.
  - Observes timer ticks and fires `onFailed("Session expired")` at expiry.
- Scope per flow:
  - PIN flows: `PinSet`
  - Payment/CPQRC: `Transaction`
  - Transfer: `LinkBank`
  - Apply Prepaid Card: `CardIssue`
- Per-flow wToken overloads provided to mirror Android usage.

## Presentation & Navigation
- `Init/Routes.swift`:
  - `Route`: `.splash`, `.intro`, `.changePin`, `.forgotPin`, `.pinSetup(VerifyOTPType)`, `.verifyOTP(VerifyOTPType)`
  - `VerifyOTPType`: `.setPin`, `.changePin`, `.forgotPin`, `.cpqrcPayment`
  - `Coordinating` protocol
- `Init/MainCoordinator.swift`:
  - Owns a `UINavigationController` and maps `Route` to VCs. Implements a Splash overlay (added/removed with fade) to avoid flicker when transitioning to the first real screen.
  - `.intro` pushes `WelcomeVC`, which then proceeds to OTP via a tap handler.
  - `.changePin` and `.forgotPin` are wired to push `ChangePINVC`/`ForgetPinVC`.
  - `closeSDK(withError:)` calls facade `onFailed` and dismisses.
  - `closeSDKSuccessWithResult(_:)` dismisses UI and then calls facade `onSuccess` with payload.
- `Init/SDKPresenter.swift`:
  - `NavigationArgs`: method type, wToken, language, environment, paymentReference, clientId/secret, phone, transferInfo, cardProductCode, cardPromoCode, cardDeliveryAddress.
  - Sets global config (lang/env/wToken) and callbacks, stores `CBSDKDataStorage.shared.navigationArgs = args`.
  - Creates `MainCoordinator` and presents nav.
  - `SDKStartRouteDecider` derives start route from args (adjust per flow).
- `UIModules/Splash/SplashVC.swift`:
  - Receives `NavigationArgs` from coordinator.
  - Calls `clientVerification`; on success, routes by `args.type`.
  - On failure, triggers `onFailed` and dismiss via coordinator.

## Networking
- `Utility/API Handler/Config.swift`:
  - `Environment.demo/live` with base URLs.
  - `CashBabaConfig` holds language, scope, wToken, accessToken.
- `Utility/API Handler/ApiPaths.swift`:
  - All endpoints including CPQRC validate/verify builders.
- `Utility/API Handler/APIHandler.swift`:
  - Default headers: `lang`, `scope`, `w-token`, `Authorization` (Bearer).
  - Methods: GET, POST form (`application/x-www-form-urlencoded`), POST multipart.
  - Multipart supports filenames/MIME (`MultipartPart`).
  - Error mapping policy:
    - 200/201 → success → `onSuccess` with raw `Data?`.
    - 401 → Unauthorized → APIHandler calls `CashBabaSDK.shared.closeSdkOnFailed(...)`, then `onFailure`.
    - 444/500/501 → Fatal → APIHandler calls `CashBabaSDK.shared.closeSdkOnFailed(...)`, then `onFailure`.
    - Other HTTP → parse `BaseResponse` for message and call `onFailure(message)` without closing.
    - Note: the multipart overload with `parts: [MultipartPart]` currently does not auto-close on 401/444 and returns the error message; upstream `WebServiceHandler` often performs the close in its `onFailure` handlers.
- `Utility/API Handler/Encryptor.swift`:
  - RSA PKCS#1 using SecKey; initialize with PEM.
- `Utility/API Handler/Models.swift`:
  - Codable responses mirroring Android; includes BaseResponse, token, PIN flows, payment, transfer, CPQRC.
- `Utility/API Handler/WebServiceHandler.swift`:
  - Composes form bodies and multipart; performs centralized PIN encryption just-in-time.
  - CPQRC multipart adds filenames and MIME detection.
  - On `validateCpQrcPayment` success, caches `cpqrcValidationData` to `CBSDKDataStorage`.
  - On `forgotPinOtpVerify` success, caches `forgetPinIdentifier` to `CBSDKDataStorage`.

## Repository
- `Utility/CBRepository/*` implements `CashBabaRepository` and `CashBabaRepositoryImpl` delegating to `WebServiceHandler`.

## Data Storage & Session
- `Utility/CBSDKDataStorage.swift` (Android DataStorage parity):
  - `navigationArgs`, `accessToken`, `languageCode`, `forgetPinIdentifier`, `environment`, `baseURL`, `tokenExpireInMillis`, `cpqrcValidationData`, `smileFacePath`, `blinkFacePath`.
  - Bridges to `SessionStore` and `APIHandler.config`.
- `Utility/CBSessionStore` (SessionStore):
  - Holds `accessToken`, `tokenExpiry` and computed `isTokenExpired`.
- `Utility/CommonUI/BaseVC/SessionTimerManager.swift`:
  - 1-second timer with `remainingSeconds`; posts `sessionTimerDidTick` notification each tick; used by facade to surface expiry.
 - Language:
   - `SplashVC` switches language using `CBSDKLanguageHandler.sharedInstance` based on `args.languageCode` ("en" or "bn").
   - `BaseViewController` conforms to `CBSDKLanguageDelegate` to react to language changes and updates UI elements (e.g., timer label) accordingly.

## UI Modules
- Splash:
  - Drives entry verification and routes to next screen according to flow.
- PIN Setup:
  - UI for setting PIN; calls facade APIs. PIN plaintext sent to `WebServiceHandler` where it is encrypted.
- Change PIN, Forget PIN, OTP Verification, Welcome/TnC:
  - Feature-specific VCs & views; all should hold `weak var coordinator: Coordinating?` for navigation.
- Confirm PIN:
  - Shared screen for Payment, Distributor Payment, Transfer, and Apply Prepaid Card flows.
  - Subtitle dynamically updates based on `MethodTypes` (e.g., "Enter your CashBaba PIN to apply for card" for `.APPLY_PREPAID_CARD`).
  - `onSubmit` dispatches to the correct repository method per flow type.

## CPQRC Payment Flow
- **Entry:** Host app calls `SDKPresenter.present(args:)` with `type: .CPQRC`, providing `paymentReference` and `phone`.
- **Splash:** Sets scope to `Transaction`, performs `clientVerification`, then calls `coordinator?.startCpqrcFlow(from: self)`.
- **Validate:** `MainCoordinator.startCpqrcFlow()` validates `paymentReference`, calls `cpqrcValidate` API (GET). Caches `cpqrcValidationData` to `CBSDKDataStorage`.
- **Face KYC (conditional):** If `isFaceVerificationRequired == true`, launches `CBFaceDetectionSDK` → captures smile/blink images → stores file paths in `CBSDKDataStorage`. If user cancels KYC, SDK closes.
- **OTP:** Navigates to `OTPVerificationVC(.cpqrcPayment)`. Timer uses `otpExpirySeconds` from validation response. Resend calls `cpqrcResendOtp(transactionId:)`.
- **Confirm → Verify chain (Android parity):**
  1. On OTP submit, calls `cpqrcConfirm` (multipart POST with `TransactionId`, `Otp`, optional smile/blink image files).
  2. After confirm (success or non-401 failure), always calls `cpqrcVerify` (GET) to check final payment status.
  3. If verify returns `code == 200` and `data.status == "Authorized"`: wraps `CpqrcValidationResponse` in `OnSuccessModel.forCpqrc(...)` and calls `closeSDKSuccessWithResult` → fires `onSuccess`.
  4. Otherwise: calls `closeSdkOnFailed` → fires `onFailed`.
- **Model:** `CpqrcValidationResponse` has `code`, `messages`, `data: CpqrcValidationData` (with `transactionId`, `isFaceVerificationRequired`, `status`, `otpExpirySeconds`, etc.).

## Apply Prepaid Card Flow
- **Entry:** Host app calls `SDKPresenter.present(args:)` with `type: .APPLY_PREPAID_CARD`, providing `cardProductCode`, `cardDeliveryAddress`, and optional `cardPromoCode`.
- **Splash:** Sets scope to `CardIssue`, performs `clientVerification`, then validates that `cardProductCode` and `cardDeliveryAddress` are non-empty (fails with localized error if missing).
- **Confirm PIN:** Routes to `ConfirmPINVC`, which shows a card-specific subtitle. On PIN submit, encrypts PIN and calls `applyForPrepaidCard` API (`v1/transaction/bankcardissuingrequest`) with `ContactAddress`, `ProductCode`, `Pin`, and optional `PromoCode`.
- **Success:** Wraps `ApplyPrepaidCardResponse` in `OnSuccessModel.forApplyPrepaidCard(...)` and calls `closeSDKSuccessWithResult`.
- **Failure:** Shows error popup (non-fatal) or closes SDK (fatal 401/444/500/501).
- **Model:** `ApplyPrepaidCardResponse` has `code: Int?`, `messages: [String]?`, `details: String?`.

## Error Handling
- Errors funnel through `SDKError` with factories (`unauthorized`, `network`, `server`, etc.).
- APIHandler centralizes FATAL closures only for: 401, 444, 500, 501.
  - These trigger `CashBabaSDK.shared.closeSdkOnFailed(message)`; host should dismiss UI via `SDKPresenter`/Coordinator wrapping.
- Non-fatal errors (e.g., 400/404/409/422) are surfaced to the caller without closing:
  - `WebServiceHandler` decodes to specific response model (or `BaseResponse`) and completes with `.failure`.
  - ViewControllers (e.g., `PINSetupVC`, `OTPVerificationVC`) display inline UI (popup/alert/label) and keep SDK open.
- Facade dispatches completions on main thread for UI safety.

### When does the SDK close?
- Centralized close conditions (from APIHandler):
  - 401 Unauthorized
  - 444 Business-fatal
  - 500/501 Server errors
- UI-initiated close:
  - Coordinator `closeSDK(withError:)` to dismiss and forward `onFailed`.
  - Coordinator `closeSDKSuccessWithResult(_:)` to dismiss and then call `onSuccess` with the success payload (used on HTTP 200 success for PIN flows).
  - Coordinator `closeSDKSuccess()` to dismiss and call `onUserCancel` (used for user-initiated back/close without payload).

### Screen-level handling examples
- PINSetupVC:
  - Success (200) → build `OnSuccessModel` and call `coordinator?.closeSDKSuccessWithResult(...)` (no success popup).
  - Failure (non-fatal) → show `CBErrorVC` popup; do not close SDK.
- ChangePINVC:
  - Success (200) → build `OnSuccessModel` and call `coordinator?.closeSDKSuccessWithResult(...)` (no success popup).
  - Failure (non-fatal) → show `CBErrorVC` popup; do not close SDK.
- OTPVerificationVC:
  - For `.setPin`/`.forgotPin`: mirrored behavior with PINSetupVC for verify/resend flows (non-fatal errors shown inline).
  - For `.cpqrcPayment`: chains `cpqrcConfirm` → `verifyCpqrcPayment()` → checks `status == "Authorized"` → `closeSDKSuccessWithResult` with `OnSuccessModel.forCpqrc(...)`.

### Back navigation and callbacks (CoordinatorAccessible)
- Base rule: closing the SDK must route through the Coordinator so `onUserCancel`/`onFailed`/`onSuccess` fire back to the host app appropriately.
- Implementation pattern:
  - Protocol in `Routes.swift`:
    - `public protocol CoordinatorAccessible { var coordinator: Coordinating? { get } }`
  - All SDK VCs should conform and expose `weak var coordinator: Coordinating?`.
  - `BaseViewController.backButtonTapped()` logic:
    - If not root: `navigationController.popViewController(animated: true)`.
    - If root and `CoordinatorAccessible`: call helper `coordinatorCloseSDKSuccess()` which invokes `coordinator?.closeSDKSuccess()`.
    - Fallback: `dismiss(animated: true)` then invoke `CashBabaSDK.shared.onUserCancel?()`.
- Outcome: ExternalVC receives callbacks consistently; success flows use `closeSDKSuccessWithResult(_:)` to emit `onSuccess` with payload.

## Flow Scopes & Headers
- Scope header is set automatically in facade per flow.
- `wToken` must be set before protected flows; per-flow overloads set it automatically.
- `lang` header is kept in sync with `APIHandler.config.languageCode`.

## Session Expiry
- On auth success, `SessionTimerManager` starts with `expiresIn`.
- Facade also starts a one-shot timer and observes tick notifications.
- When expired, fires `onFailed("Session expired")` and the UI is expected to dismiss via coordinator.

## Extensibility To-Dos
- Confirm OTP field key casing with backend and adjust if needed.
- Adjust `SDKStartRouteDecider` mapping for TRANSFER/PAYMENT/CPQRC to exact entry screens.
- Ensure all VCs include `coordinator` property and transition via coordinator.
- Optional: add logging switches and retry/backoff, and unit tests with a mock transport.

## Quick Usage
```swift
// Load PEM and init SDK once
try CashBabaSDK.shared.initialize(environment: .demo, languageCode: "en", pemResourceName: "publickey.pem")

// Present SDK from host — Set PIN example
let args = NavigationArgs(
  type: .SET_PIN,
  wToken: "<w-token>",
  languageCode: "en",
  environment: .demo,
  clientId: "cb_merchant_sdk",
  clientSecret: "Abcd@1234"
)
SDKPresenter.present(from: hostController, args: args, onSuccess: { result in
  // handle success
}, onFailed: { failure in
  // show failure.errorMessage
}, onUserCancel: {
  // user closed
})

// Apply Prepaid Card example
let cardArgs = NavigationArgs(
  type: .APPLY_PREPAID_CARD,
  wToken: "<w-token>",
  languageCode: "en",
  environment: .demo,
  clientId: "cb_merchant_sdk",
  clientSecret: "Abcd@1234",
  cardProductCode: "PROD001",
  cardPromoCode: "PROMO10",       // optional
  cardDeliveryAddress: "123 Main St"
)
SDKPresenter.present(from: hostController, args: cardArgs, onSuccess: { result in
  // result.applyPrepaidCardResponse contains code, messages, details
}, onFailed: { failure in
  // show failure.errorMessage
}, onUserCancel: {
  // user closed
})
```
