;; Quantum Research Ethics Contract
;; Governs quantum computing research to prevent harmful applications

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u301))
(define-constant ERR-INVALID-PROPOSAL (err u302))
(define-constant ERR-ALREADY-REVIEWED (err u303))
(define-constant ERR-INSUFFICIENT-REVIEWERS (err u304))
(define-constant ERR-RESEARCHER-NOT-FOUND (err u305))

;; Data Variables
(define-data-var total-proposals uint u0)
(define-data-var total-researchers uint u0)
(define-data-var admin principal CONTRACT-OWNER)
(define-data-var min-reviewers uint u3)
(define-data-var review-period uint u604800) ;; 7 days in seconds

;; Data Maps
(define-map research-proposals
  { proposal-id: uint }
  {
    researcher: principal,
    title: (string-ascii 128),
    description: (string-ascii 512),
    risk-level: uint,
    research-category: (string-ascii 64),
    status: (string-ascii 32),
    submitted-at: uint,
    review-deadline: uint,
    approved-reviewers: uint,
    rejected-reviewers: uint,
    final-decision: (string-ascii 32)
  }
)

(define-map researchers
  { researcher: principal }
  {
    name: (string-ascii 64),
    institution: (string-ascii 128),
    credentials: (string-ascii 256),
    clearance-level: uint,
    active-proposals: uint,
    approved-proposals: uint,
    rejected-proposals: uint,
    registered-at: uint,
    last-activity: uint
  }
)

(define-map proposal-reviews
  { proposal-id: uint, reviewer: principal }
  {
    decision: (string-ascii 32),
    comments: (string-ascii 256),
    risk-assessment: uint,
    reviewed-at: uint,
    confidence-level: uint
  }
)

(define-map ethics-guidelines
  { guideline-id: uint }
  {
    title: (string-ascii 128),
    description: (string-ascii 512),
    category: (string-ascii 64),
    severity-level: uint,
    active: bool,
    created-at: uint
  }
)

(define-map reviewer-pool
  { reviewer: principal }
  {
    expertise-areas: (string-ascii 256),
    review-count: uint,
    approval-rate: uint,
    last-review: uint,
    active: bool
  }
)

;; Private Functions
(define-private (is-admin (user principal))
  (is-eq user (var-get admin))
)

(define-private (is-authorized-reviewer (reviewer principal))
  (is-some (map-get? reviewer-pool { reviewer: reviewer }))
)

(define-private (validate-risk-level (risk uint))
  (and (>= risk u1) (<= risk u10))
)

(define-private (calculate-approval-rate (approved uint) (total uint))
  (if (> total u0)
    (/ (* approved u100) total)
    u0
  )
)

;; Public Functions

;; Register as a researcher
(define-public (register-researcher
  (name (string-ascii 64))
  (institution (string-ascii 128))
  (credentials (string-ascii 256)))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (> (len name) u0) ERR-INVALID-PROPOSAL)
    (asserts! (> (len institution) u0) ERR-INVALID-PROPOSAL)

    (map-set researchers
      { researcher: tx-sender }
      {
        name: name,
        institution: institution,
        credentials: credentials,
        clearance-level: u1,
        active-proposals: u0,
        approved-proposals: u0,
        rejected-proposals: u0,
        registered-at: current-time,
        last-activity: current-time
      }
    )
    (var-set total-researchers (+ (var-get total-researchers) u1))
    (ok true)
  )
)

;; Submit research proposal
(define-public (submit-proposal
  (title (string-ascii 128))
  (description (string-ascii 512))
  (risk-level uint)
  (category (string-ascii 64)))
  (let
    (
      (proposal-id (+ (var-get total-proposals) u1))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (review-deadline (+ current-time (var-get review-period)))
      (researcher-data (unwrap! (map-get? researchers { researcher: tx-sender }) ERR-RESEARCHER-NOT-FOUND))
    )
    (asserts! (> (len title) u0) ERR-INVALID-PROPOSAL)
    (asserts! (> (len description) u0) ERR-INVALID-PROPOSAL)
    (asserts! (validate-risk-level risk-level) ERR-INVALID-PROPOSAL)

    (map-set research-proposals
      { proposal-id: proposal-id }
      {
        researcher: tx-sender,
        title: title,
        description: description,
        risk-level: risk-level,
        research-category: category,
        status: "under-review",
        submitted-at: current-time,
        review-deadline: review-deadline,
        approved-reviewers: u0,
        rejected-reviewers: u0,
        final-decision: "pending"
      }
    )

    ;; Update researcher stats
    (map-set researchers
      { researcher: tx-sender }
      (merge researcher-data {
        active-proposals: (+ (get active-proposals researcher-data) u1),
        last-activity: current-time
      })
    )

    (var-set total-proposals proposal-id)
    (ok proposal-id)
  )
)

;; Submit proposal review
(define-public (submit-review
  (proposal-id uint)
  (decision (string-ascii 32))
  (comments (string-ascii 256))
  (risk-assessment uint)
  (confidence uint))
  (let
    (
      (proposal (unwrap! (map-get? research-proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (reviewer-data (unwrap! (map-get? reviewer-pool { reviewer: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-authorized-reviewer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status proposal) "under-review") ERR-ALREADY-REVIEWED)
    (asserts! (< current-time (get review-deadline proposal)) ERR-INVALID-PROPOSAL)
    (asserts! (validate-risk-level risk-assessment) ERR-INVALID-PROPOSAL)
    (asserts! (<= confidence u100) ERR-INVALID-PROPOSAL)
    (asserts! (is-none (map-get? proposal-reviews { proposal-id: proposal-id, reviewer: tx-sender })) ERR-ALREADY-REVIEWED)

    ;; Record the review
    (map-set proposal-reviews
      { proposal-id: proposal-id, reviewer: tx-sender }
      {
        decision: decision,
        comments: comments,
        risk-assessment: risk-assessment,
        reviewed-at: current-time,
        confidence-level: confidence
      }
    )

    ;; Update proposal review counts
    (let
      (
        (new-approved (if (is-eq decision "approve")
          (+ (get approved-reviewers proposal) u1)
          (get approved-reviewers proposal)))
        (new-rejected (if (is-eq decision "reject")
          (+ (get rejected-reviewers proposal) u1)
          (get rejected-reviewers proposal)))
      )
      (map-set research-proposals
        { proposal-id: proposal-id }
        (merge proposal {
          approved-reviewers: new-approved,
          rejected-reviewers: new-rejected
        })
      )
    )

    ;; Update reviewer stats
    (map-set reviewer-pool
      { reviewer: tx-sender }
      (merge reviewer-data {
        review-count: (+ (get review-count reviewer-data) u1),
        last-review: current-time
      })
    )

    (ok true)
  )
)

;; Finalize proposal decision
(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? research-proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
      (total-reviews (+ (get approved-reviewers proposal) (get rejected-reviewers proposal)))
      (researcher (get researcher proposal))
      (researcher-data (unwrap! (map-get? researchers { researcher: researcher }) ERR-RESEARCHER-NOT-FOUND))
    )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= total-reviews (var-get min-reviewers)) ERR-INSUFFICIENT-REVIEWERS)
    (asserts! (is-eq (get status proposal) "under-review") ERR-ALREADY-REVIEWED)

    (let
      (
        (final-decision (if (> (get approved-reviewers proposal) (get rejected-reviewers proposal)) "approved" "rejected"))
      )
      ;; Update proposal status
      (map-set research-proposals
        { proposal-id: proposal-id }
        (merge proposal {
          status: "completed",
          final-decision: final-decision
        })
      )

      ;; Update researcher stats
      (map-set researchers
        { researcher: researcher }
        (merge researcher-data {
          active-proposals: (- (get active-proposals researcher-data) u1),
          approved-proposals: (if (is-eq final-decision "approved")
            (+ (get approved-proposals researcher-data) u1)
            (get approved-proposals researcher-data)),
          rejected-proposals: (if (is-eq final-decision "rejected")
            (+ (get rejected-proposals researcher-data) u1)
            (get rejected-proposals researcher-data))
        })
      )

      (ok final-decision)
    )
  )
)

;; Admin function to add reviewer to pool
(define-public (add-reviewer
  (reviewer principal)
  (expertise (string-ascii 256)))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len expertise) u0) ERR-INVALID-PROPOSAL)

    (map-set reviewer-pool
      { reviewer: reviewer }
      {
        expertise-areas: expertise,
        review-count: u0,
        approval-rate: u0,
        last-review: u0,
        active: true
      }
    )
    (ok true)
  )
)

;; Create ethics guideline
(define-public (create-guideline
  (guideline-id uint)
  (title (string-ascii 128))
  (description (string-ascii 512))
  (category (string-ascii 64))
  (severity uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len title) u0) ERR-INVALID-PROPOSAL)
    (asserts! (<= severity u10) ERR-INVALID-PROPOSAL)

    (map-set ethics-guidelines
      { guideline-id: guideline-id }
      {
        title: title,
        description: description,
        category: category,
        severity-level: severity,
        active: true,
        created-at: current-time
      }
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? research-proposals { proposal-id: proposal-id })
)

(define-read-only (get-researcher (researcher principal))
  (map-get? researchers { researcher: researcher })
)

(define-read-only (get-review (proposal-id uint) (reviewer principal))
  (map-get? proposal-reviews { proposal-id: proposal-id, reviewer: reviewer })
)

(define-read-only (get-guideline (guideline-id uint))
  (map-get? ethics-guidelines { guideline-id: guideline-id })
)

(define-read-only (get-reviewer (reviewer principal))
  (map-get? reviewer-pool { reviewer: reviewer })
)

(define-read-only (get-total-proposals)
  (var-get total-proposals)
)

(define-read-only (get-total-researchers)
  (var-get total-researchers)
)
