# Push Registration

Tells Sendr, the notification backend, where to deliver push notifications for this device.

Everything here is gated on `enableProvisionalNotifications`. With the flag off, the legacy path
in `PushDelegate` and `RBPushRegistrationHelper` runs instead.

## Design

The full registration state is three values: the OS authorization status, the APNs device token, and
the number of logouts since launch. That last one stands in for Sendr's auth session ID, which the
app has no way to read.

The work splits along that boundary:

- `PushRegistrationCoordinator` turns OS, app, and account lifecycle events into those triples.
- `PushRegistrationSendrQueue` turns the stream of triples into the fewest HTTP requests that get the
  server there, deduplicating, pacing, and retrying along the way.

The coordinator never decides which Sendr call to make. It describes where the server should end up;
the queue works out whether getting there means a register, a deregister, or nothing at all. Triggers
can therefore be liberal, since firing twice for one change costs nothing.

Sendr offers no way to ask whether a registration still exists, so the queue's idea of what the server
holds is in-memory only and a fresh process always sends once. That is how the app recovers when
Sendr's record of the device went away while we were not running.

Every field of `PushRegistrationState` describes something observable — what the OS reports, what APNs
issued, which session this is. None of them records intent, which is why a user tapping "enable
notifications" adds no field: whatever their tap changes about the world shows up in those three, and
if it changes nothing then there is nothing to tell Sendr.

### The session epoch

Sendr binds a registration to the auth session the request arrived on, and the app has no way to read
a session ID, so the logout counter stands in for one. A session is only ever replaced by a login,
logout, account switch, or involuntary logout, and all four reach the coordinator as a logout first.

Carrying it in the state rather than keeping it as a side effect on some ledger is the point: there is
no ordering to get wrong between "forget what was sent" and "send the next thing". It also makes a
permanent rejection expire on its own, since a new session simply produces a value the queue has never
refused.

## Triggers

Three situations need to reach Sendr, and `activate()` has a trigger for each:

- **The app launched with a logged-in user.** `RBX_NOTIFY_LOGIN_SUCCEEDED`, which the startup session
  check posts, plus a direct check in `activate()` in case it runs after that has happened.
- **The user logged in or switched accounts.** `RBX_NOTIFY_LOGIN_SUCCEEDED` again. The logout that
  necessarily precedes it bumped the epoch, so the resulting state is new.
- **The user changed the notification setting in the Settings app.** `willEnterForeground`, after
  which the OS status is re-read and only an actual change is sent.

All three are gated on there being a signed-in user, because Sendr identifies the device's owner from
the request's auth cookie and can do nothing without one.

Nothing watches the auth cookie itself. Authentication invalidates a session only on login, logout,
account switch, and involuntary logout, and all four post one of the two notifications above, so the
cookie carries no signal these do not. It is also noisier: the cookie is rotated without the session
ID changing, which needs no registration at all.

Sendr reassigns a device to whichever user registered it most recently, so an account switch needs no
handling beyond registering as the new user.

## Entry points

Nothing outside this directory should call anything but these.

| Caller | Call |
| --- | --- |
| `AppDependencyManager` | `PushRegistrationCoordinator.init(...)`, then `PushRegistrationProvider.register(coordinator:)`, then `activate()` |
| `AppDelegateROMA` | `didRegisterForRemoteNotifications(withDeviceToken:)` |
| `AppDelegateROMA` | `didFailToRegisterForRemoteNotifications(withError:)` |
| Opt-in UI, via `PushRegistrationProvider.currentCoordinator()` | `registerForPushNotifications()` |

`registerForPushNotifications()` is the only entry point that can put the system permission prompt on
screen, so call it only from an explicit user action. Lifecycle triggers take provisional
authorization silently instead, which is what keeps a login or a resume from prompting out of nowhere.

Its callers are `RBPushPermissionsViewController`, `RBHybridEventNotificationObserver`,
`RBIOSPermissionsProtocol`, and `RBPushRegistrationHelper`.

## Files

| File | Role |
| --- | --- |
| `PushRegistrationCoordinator.swift` | Lifecycle observers; builds the state triples |
| `PushRegistrationSendrQueue.swift` | Actor: dedup, single-flight, pacing, retry |
| `PushRegistrationSendrQueueBridge.swift` | Lets synchronous callers hand work to that actor in order |
| `PushRegistrationState.swift` | The triple |
| `PushRegistrationProvider.swift` | Static bridge so ObjC call sites can reach the coordinator |
| `PushRegistrationRequester.swift` | Seam over the two `RBBaseRequest` subclasses |
| `PushRegistrationOutcome.swift` | Success, permanent rejection, or retryable |
| `PushRegistrationClock.swift` | Injectable clock, so tests need not wait out pacing or backoff |
| `PushNotificationState.swift` | The app's persisted record, and its on-disk encoding |
| `PushNotificationStateRecorder.swift` | Keeps that record in step with what Sendr was told |
| `AuthenticationState.swift` | Whether a user is signed in |
| `UNAuthorizationStatus+LogDescription.swift` | Readable authorization status in logs |

`UserNotificationCenterProtocol` and `RemoteNotificationRegistering`, the seams over
`UNUserNotificationCenter` and `UIApplication`, live in `Core/Utilities/SystemAPIWrappers`.

## Threading

The coordinator's mutable state is main-thread confined, and `onMain` guards every entry that can
arrive off it.

The queue is an actor, and every caller today is synchronous main-thread code, so calls reach it
through `PushRegistrationSendrQueueBridge`. That indirection exists for ordering. Hopping onto an
actor from synchronous code means an unstructured task, and unstructured tasks carry no ordering
relative to one another, so two enqueues in quick succession can arrive reversed and leave the queue
settled on the older of the two — the opposite of what latest-wins is meant to guarantee. The bridge
stamps each call in call order and the actor ignores anything older than what it has already seen.
Cancels are stamped for the same reason: a cancel that overtook the login behind it would throw away
the new session's registration and leave nothing to re-send it.

The bridge is meant to be temporary. When every call site can await the queue directly, it and the
stamps go away, and the lock behind the stamps goes with them.

## Testing seams

`PushRegistrationRequesting` is a seam rather than a passthrough. The requests themselves are
`RBBaseRequest` subclasses, which take their completion blocks in the initializer — so there is no
request object to substitute in a test, only a factory for one — and which carry their own retry and
session-manager machinery that a fake would inherit by subclassing. Keeping a protocol in front of
them means the queue can be tested against three outcomes instead of against AFNetworking, and its
retry logic is not competing with the base class's.

`NotificationCenter` and `UNUserNotificationCenter` are both constructor dependencies, and the tests
pass a fresh `NotificationCenter()` rather than `.default`, so no test reads or writes global
notification state and the suites are safe to run in parallel.

## Tests

In `RobloxTests/Push`: `PushRegistrationCoordinatorTests`, `PushRegistrationSendrQueueTests`, and
`PushRegistrationInFlightTests`, which covers logout and token rotation while a request is in flight.
Shared fakes are in `PushRegistrationFakes`.
