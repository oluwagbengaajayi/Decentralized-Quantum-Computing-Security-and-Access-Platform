;; Quantum Computing Access Equity Contract
;; Ensures fair access to quantum computing resources

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSUFFICIENT-QUOTA (err u201))
(define-constant ERR-INVALID-REQUEST (err u202))
(define-constant ERR-REQUEST-NOT-FOUND (err u203))
(define-constant ERR-RESOURCE-UNAVAILABLE (err u204))
(define-constant ERR-INVALID-PRIORITY (err u205))

;; Data Variables
(define-data-var total-requests uint u0)
(define-data-var total-resources uint u1000)
(define-data-var available-resources uint u1000)
(define-data-var admin principal CONTRACT-OWNER)
(define-data-var base-quota uint u10)

;; Data Maps
(define-map access-requests
  { request-id: uint }
  {
    requester: principal,
    resource-amount: uint,
    priority-level: uint,
    purpose: (string-ascii 128),
    status: (string-ascii 32),
    requested-at: uint,
    allocated-at: uint,
    expires-at: uint
  }
)

(define-map user-quotas
  { user: principal }
  {
    allocated-quota: uint,
    used-quota: uint,
    priority-bonus: uint,
    last-allocation: uint,
    total-requests: uint
  }
)

(define-map resource-pools
  { pool-id: (string-ascii 32) }
  {
    total-capacity: uint,
    available-capacity: uint,
    reserved-capacity: uint,
    pool-type: (string-ascii 32),
    access-level: uint
  }
)

(define-map priority-groups
  { group-id: (string-ascii 32) }
  {
    name: (string-ascii 64),
    priority-multiplier: uint,
    quota-bonus: uint,
    member-count: uint
  }
)

;; Private Functions
(define-private (is-admin (user principal))
  (is-eq user (var-get admin))
)

(define-private (calculate-priority-score (base-priority uint) (user-bonus uint))
  (+ base-priority user-bonus)
)

(define-private (validate-resource-amount (amount uint))
  (and (> amount u0) (<= amount u100))
)

(define-private (get-user-effective-quota (user principal))
  (let
    (
      (user-data (default-to
        { allocated-quota: (var-get base-quota), used-quota: u0, priority-bonus: u0, last-allocation: u0, total-requests: u0 }
        (map-get? user-quotas { user: user })
      ))
    )
    (+ (get allocated-quota user-data) (get priority-bonus user-data))
  )
)

;; Public Functions

;; Request quantum computing access
(define-public (request-access
  (resource-amount uint)
  (purpose (string-ascii 128))
  (priority uint))
  (let
    (
      (request-id (+ (var-get total-requests) u1))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (user-quota (get-user-effective-quota tx-sender))
      (user-data (default-to
        { allocated-quota: (var-get base-quota), used-quota: u0, priority-bonus: u0, last-allocation: u0, total-requests: u0 }
        (map-get? user-quotas { user: tx-sender })
      ))
    )
    (asserts! (validate-resource-amount resource-amount) ERR-INVALID-REQUEST)
    (asserts! (<= priority u10) ERR-INVALID-PRIORITY)
    (asserts! (> (len purpose) u0) ERR-INVALID-REQUEST)
    (asserts! (<= (+ (get used-quota user-data) resource-amount) user-quota) ERR-INSUFFICIENT-QUOTA)

    (map-set access-requests
      { request-id: request-id }
      {
        requester: tx-sender,
        resource-amount: resource-amount,
        priority-level: priority,
        purpose: purpose,
        status: "pending",
        requested-at: current-time,
        allocated-at: u0,
        expires-at: u0
      }
    )

    (var-set total-requests request-id)
    (ok request-id)
  )
)

;; Allocate resources to approved request
(define-public (allocate-resources (request-id uint) (duration-hours uint))
  (let
    (
      (request (unwrap! (map-get? access-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (expiry-time (+ current-time (* duration-hours u3600)))
      (resource-amount (get resource-amount request))
    )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-REQUEST)
    (asserts! (>= (var-get available-resources) resource-amount) ERR-RESOURCE-UNAVAILABLE)

    ;; Update request status
    (map-set access-requests
      { request-id: request-id }
      (merge request {
        status: "allocated",
        allocated-at: current-time,
        expires-at: expiry-time
      })
    )

    ;; Update user quota usage
    (let
      (
        (user (get requester request))
        (user-data (default-to
          { allocated-quota: (var-get base-quota), used-quota: u0, priority-bonus: u0, last-allocation: current-time, total-requests: u1 }
          (map-get? user-quotas { user: user })
        ))
      )
      (map-set user-quotas
        { user: user }
        (merge user-data {
          used-quota: (+ (get used-quota user-data) resource-amount),
          last-allocation: current-time,
          total-requests: (+ (get total-requests user-data) u1)
        })
      )
    )

    ;; Update available resources
    (var-set available-resources (- (var-get available-resources) resource-amount))
    (ok true)
  )
)

;; Release resources when usage is complete
(define-public (release-resources (request-id uint))
  (let
    (
      (request (unwrap! (map-get? access-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (resource-amount (get resource-amount request))
      (user (get requester request))
    )
    (asserts! (or (is-admin tx-sender) (is-eq tx-sender user)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "allocated") ERR-INVALID-REQUEST)

    ;; Update request status
    (map-set access-requests
      { request-id: request-id }
      (merge request { status: "completed" })
    )

    ;; Return resources to available pool
    (var-set available-resources (+ (var-get available-resources) resource-amount))
    (ok true)
  )
)

;; Admin function to set user quota
(define-public (set-user-quota (user principal) (new-quota uint))
  (let
    (
      (user-data (default-to
        { allocated-quota: (var-get base-quota), used-quota: u0, priority-bonus: u0, last-allocation: u0, total-requests: u0 }
        (map-get? user-quotas { user: user })
      ))
    )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> new-quota u0) ERR-INVALID-REQUEST)

    (map-set user-quotas
      { user: user }
      (merge user-data { allocated-quota: new-quota })
    )
    (ok true)
  )
)

;; Create priority group for underrepresented users
(define-public (create-priority-group
  (group-id (string-ascii 32))
  (name (string-ascii 64))
  (priority-multiplier uint)
  (quota-bonus uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len group-id) u0) ERR-INVALID-REQUEST)
    (asserts! (> priority-multiplier u0) ERR-INVALID-REQUEST)

    (map-set priority-groups
      { group-id: group-id }
      {
        name: name,
        priority-multiplier: priority-multiplier,
        quota-bonus: quota-bonus,
        member-count: u0
      }
    )
    (ok true)
  )
)

;; Add user to priority group
(define-public (add-to-priority-group (user principal) (group-id (string-ascii 32)))
  (let
    (
      (group (unwrap! (map-get? priority-groups { group-id: group-id }) ERR-REQUEST-NOT-FOUND))
      (user-data (default-to
        { allocated-quota: (var-get base-quota), used-quota: u0, priority-bonus: u0, last-allocation: u0, total-requests: u0 }
        (map-get? user-quotas { user: user })
      ))
    )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    ;; Update user with priority bonus
    (map-set user-quotas
      { user: user }
      (merge user-data { priority-bonus: (get quota-bonus group) })
    )

    ;; Update group member count
    (map-set priority-groups
      { group-id: group-id }
      (merge group { member-count: (+ (get member-count group) u1) })
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-access-request (request-id uint))
  (map-get? access-requests { request-id: request-id })
)

(define-read-only (get-user-quota (user principal))
  (map-get? user-quotas { user: user })
)

(define-read-only (get-available-resources)
  (var-get available-resources)
)

(define-read-only (get-total-resources)
  (var-get total-resources)
)

(define-read-only (get-priority-group (group-id (string-ascii 32)))
  (map-get? priority-groups { group-id: group-id })
)

(define-read-only (get-user-effective-quota-public (user principal))
  (get-user-effective-quota user)
)
