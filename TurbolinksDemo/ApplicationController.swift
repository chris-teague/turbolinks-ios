import UIKit
import WebKit
import Turbolinks

class ApplicationController: UIViewController, WKNavigationDelegate, SessionDelegate, AuthenticationControllerDelegate {
    let URL = NSURL(string: "http://localhost:9292")!
    let webViewProcessPool = WKProcessPool()
    var mainNavigationController: UINavigationController?

    var application: UIApplication {
        return UIApplication.sharedApplication()
    }

    lazy var webViewConfiguration: WKWebViewConfiguration = {
        let bundle = NSBundle.mainBundle()
        let source = try! String(contentsOfURL: bundle.URLForResource("TurbolinksDemo", withExtension: "js")!, encoding: NSUTF8StringEncoding)
        let userScript = WKUserScript(source: source, injectionTime: .AtDocumentEnd, forMainFrameOnly: true)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(userScript)
        configuration.processPool = self.webViewProcessPool
        return configuration
    }()

    lazy var session: Session = {
        let session = Session(webViewConfiguration: self.webViewConfiguration)
        session.delegate = self
        return session
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        installMainNavigationController()
        presentVisitableForSession(session, URL: URL)
    }

    func installMainNavigationController() {
        let mainNavigationController = UINavigationController()
        self.mainNavigationController = mainNavigationController
        addChildViewController(mainNavigationController)
        view.addSubview(mainNavigationController.view)
        mainNavigationController.didMoveToParentViewController(self)
    }

    private func presentVisitableForSession(session: Session, URL: NSURL, action: Action = .Advance) {
        if let navigationController = mainNavigationController {
            let visitable = visitableForSession(session, URL: URL)
            let viewController = visitable.visitableViewController

            if action == .Advance {
                navigationController.pushViewController(viewController, animated: true)
            } else if action == .Replace {
                navigationController.popViewControllerAnimated(false)
                navigationController.pushViewController(viewController, animated: false)
            }

            session.visit(visitable)
        }
    }

    private func visitableForSession(session: Session, URL: NSURL) -> Visitable {
        let visitable = WebViewController()
        visitable.visitableURL = URL
        return visitable
    }

    func presentAuthenticationController() {
        let authenticationController = AuthenticationController()
        authenticationController.delegate = self
        authenticationController.URL = URL.URLByAppendingPathComponent("sign-in")
        authenticationController.title = "Sign in"

        let authNavigationController = UINavigationController(rootViewController: authenticationController)
        presentViewController(authNavigationController, animated: true, completion: nil)
    }

    // MARK: Error Handling

    private func presentAlertForError(error: NSError) {
        let alertController = UIAlertController(title: "Error loading page", message: error.localizedDescription, preferredStyle: .Alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
        presentViewController(alertController, animated: true, completion: nil)
    }

    // MARK: SessionDelegate

    func session(session: Session, didProposeVisitToURL URL: NSURL, withAction action: Action) {
        presentVisitableForSession(session, URL: URL, action: action)
    }

    func sessionDidStartRequest(session: Session) {
        application.networkActivityIndicatorVisible = true
    }

    func session(session: Session, didFailRequestForVisitable visitable: Visitable, withError error: NSError) {
        print("ERROR: \(error)")
        if error.code == ErrorCode.HTTPFailure.rawValue, let statusCode = error.userInfo["statusCode"] as? Int where statusCode == 401 {
          // Wait for the navigation controller's animation to complete before presenting
          after(500) {
            self.presentAuthenticationController()
          }
        } else {
            session.topmostVisitable?.hideVisitableActivityIndicator()
            presentAlertForError(error)
        }
    }

    func sessionDidFinishRequest(session: Session) {
        application.networkActivityIndicatorVisible = false
    }

    func sessionDidInitializeWebView(session: Session) {
        session.webView.navigationDelegate = self
    }

    // MARK: AuthenticationControllerDelegate

    func prepareWebViewConfiguration(configuration: WKWebViewConfiguration, forAuthenticationController authenticationController: AuthenticationController) {
        configuration.processPool = webViewProcessPool
    }

    func authenticationControllerDidAuthenticate(authenticationController: AuthenticationController) {
        session.reload()
        dismissViewControllerAnimated(true, completion: nil)
    }

    // MARK: WKNavigationDelegate

    func webView(webView: WKWebView, decidePolicyForNavigationAction navigationAction: WKNavigationAction, decisionHandler: (WKNavigationActionPolicy) -> ()) {
        decisionHandler(WKNavigationActionPolicy.Cancel)

        if let URL = navigationAction.request.URL {
            UIApplication.sharedApplication().openURL(URL)
        }
    }
}

private func after(msec: Int, callback: () -> ()) {
    let time = dispatch_time(DISPATCH_TIME_NOW, Int64(msec) * Int64(NSEC_PER_MSEC))
    dispatch_after(time, dispatch_get_main_queue(), callback)
}
