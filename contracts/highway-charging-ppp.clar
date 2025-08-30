;; title: Smart Highway EV Charging PPP Contract
;; version: 1.0.0
;; summary: Public-private partnership management for EV charging infrastructure
;; description: Manages financing, risk allocation, milestone tracking, and revenue sharing

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-STAKEHOLDER (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-MILESTONE-NOT-READY (err u103))
(define-constant ERR-STATION-NOT-FOUND (err u104))
(define-constant ERR-PROJECT-NOT-FOUND (err u105))
(define-constant ERR-INVALID-AMOUNT (err u106))
(define-constant ERR-CONTRACT-LOCKED (err u107))

;; Stakeholder types
(define-constant STAKEHOLDER-PUBLIC u1)
(define-constant STAKEHOLDER-PRIVATE u2)
(define-constant STAKEHOLDER-ADMIN u3)

;; Station status constants
(define-constant STATUS-PLANNED u1)
(define-constant STATUS-UNDER-CONSTRUCTION u2)
(define-constant STATUS-OPERATIONAL u3)
(define-constant STATUS-MAINTENANCE u4)
(define-constant STATUS-DECOMMISSIONED u5)

;; Milestone types
(define-constant MILESTONE-LAND-ACQUISITION u1)
(define-constant MILESTONE-PERMITS-APPROVED u2)
(define-constant MILESTONE-CONSTRUCTION-START u3)
(define-constant MILESTONE-STATION-INSTALLED u4)
(define-constant MILESTONE-OPERATIONAL u5)

;; Contract admin
(define-data-var contract-admin principal tx-sender)
(define-data-var contract-locked bool false)
(define-data-var total-projects uint u0)
(define-data-var total-stations uint u0)
(define-data-var total-revenue uint u0)

;; Stakeholder registry
(define-map stakeholders
  { address: principal }
  {
    stakeholder-type: uint,
    registration-date: uint,
    verified: bool,
    funding-capacity: uint,
    reputation-score: uint
  }
)

;; Project registry
(define-map projects
  { project-id: uint }
  {
    name: (string-ascii 64),
    public-partner: principal,
    private-partner: principal,
    total-budget: uint,
    public-funding: uint,
    private-funding: uint,
    current-milestone: uint,
    completion-percentage: uint,
    created-at: uint,
    status: uint
  }
)

;; Charging station registry
(define-map charging-stations
  { station-id: uint }
  {
    project-id: uint,
    location: (string-ascii 128),
    capacity: uint,
    installation-cost: uint,
    operational-status: uint,
    revenue-generated: uint,
    maintenance-cost: uint,
    installed-at: uint
  }
)

;; Milestone tracking
(define-map project-milestones
  { project-id: uint, milestone-type: uint }
  {
    target-date: uint,
    completion-date: uint,
    budget-allocated: uint,
    actual-cost: uint,
    completed: bool,
    verified: bool
  }
)

;; Revenue sharing configuration
(define-map revenue-sharing
  { project-id: uint }
  {
    public-share-percentage: uint,
    private-share-percentage: uint,
    total-distributed: uint,
    last-distribution: uint
  }
)

;; Fund escrow for milestone-based payments
(define-map escrow-funds
  { project-id: uint, milestone-type: uint }
  {
    amount: uint,
    depositor: principal,
    released: bool,
    release-date: uint
  }
)

;; Public function: Register stakeholder
(define-public (register-stakeholder (stakeholder-type uint) (funding-capacity uint))
  (let
    (
      (caller tx-sender)
      (current-block stacks-block-height)
    )
    (asserts! (or (is-eq stakeholder-type STAKEHOLDER-PUBLIC) (is-eq stakeholder-type STAKEHOLDER-PRIVATE)) ERR-INVALID-STAKEHOLDER)
    (map-set stakeholders
      { address: caller }
      {
        stakeholder-type: stakeholder-type,
        registration-date: current-block,
        verified: false,
        funding-capacity: funding-capacity,
        reputation-score: u100
      }
    )
    (ok true)
  )
)

;; Public function: Create new project
(define-public (create-project 
    (name (string-ascii 64)) 
    (private-partner principal) 
    (total-budget uint)
    (public-funding uint)
    (private-funding uint)
  )
  (let
    (
      (project-id (+ (var-get total-projects) u1))
      (caller tx-sender)
    )
    (asserts! (not (var-get contract-locked)) ERR-CONTRACT-LOCKED)
    (asserts! (is-some (map-get? stakeholders { address: caller })) ERR-INVALID-STAKEHOLDER)
    (asserts! (is-some (map-get? stakeholders { address: private-partner })) ERR-INVALID-STAKEHOLDER)
    (asserts! (is-eq (+ public-funding private-funding) total-budget) ERR-INVALID-AMOUNT)
    
    (map-set projects
      { project-id: project-id }
      {
        name: name,
        public-partner: caller,
        private-partner: private-partner,
        total-budget: total-budget,
        public-funding: public-funding,
        private-funding: private-funding,
        current-milestone: MILESTONE-LAND-ACQUISITION,
        completion-percentage: u0,
        created-at: stacks-block-height,
        status: STATUS-PLANNED
      }
    )
    
    ;; Set initial revenue sharing (60% private, 40% public)
    (map-set revenue-sharing
      { project-id: project-id }
      {
        public-share-percentage: u40,
        private-share-percentage: u60,
        total-distributed: u0,
        last-distribution: u0
      }
    )
    
    (var-set total-projects project-id)
    (ok project-id)
  )
)

;; Public function: Deploy charging station
(define-public (deploy-charging-station 
    (project-id uint)
    (location (string-ascii 128))
    (capacity uint)
    (installation-cost uint)
  )
  (let
    (
      (station-id (+ (var-get total-stations) u1))
      (caller tx-sender)
      (project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (not (var-get contract-locked)) ERR-CONTRACT-LOCKED)
    (asserts! (or (is-eq caller (get public-partner project)) (is-eq caller (get private-partner project))) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get current-milestone project) MILESTONE-PERMITS-APPROVED) ERR-MILESTONE-NOT-READY)
    
    (map-set charging-stations
      { station-id: station-id }
      {
        project-id: project-id,
        location: location,
        capacity: capacity,
        installation-cost: installation-cost,
        operational-status: STATUS-UNDER-CONSTRUCTION,
        revenue-generated: u0,
        maintenance-cost: u0,
        installed-at: stacks-block-height
      }
    )
    
    (var-set total-stations station-id)
    (ok station-id)
  )
)

;; Public function: Complete milestone
(define-public (complete-milestone (project-id uint) (milestone-type uint) (actual-cost uint))
  (let
    (
      (caller tx-sender)
      (project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
      (milestone (map-get? project-milestones { project-id: project-id, milestone-type: milestone-type }))
    )
    (asserts! (not (var-get contract-locked)) ERR-CONTRACT-LOCKED)
    (asserts! (or (is-eq caller (get public-partner project)) (is-eq caller (get private-partner project))) ERR-NOT-AUTHORIZED)
    
    (map-set project-milestones
      { project-id: project-id, milestone-type: milestone-type }
      {
        target-date: (default-to u0 (get target-date milestone)),
        completion-date: stacks-block-height,
        budget-allocated: (default-to u0 (get budget-allocated milestone)),
        actual-cost: actual-cost,
        completed: true,
        verified: false
      }
    )
    
    ;; Update project milestone progression
    (map-set projects
      { project-id: project-id }
      (merge project { current-milestone: (+ milestone-type u1) })
    )
    
    (ok true)
  )
)

;; Public function: Record revenue
(define-public (record-station-revenue (station-id uint) (amount uint))
  (let
    (
      (caller tx-sender)
      (station (unwrap! (map-get? charging-stations { station-id: station-id }) ERR-STATION-NOT-FOUND))
      (project-id (get project-id station))
      (project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (not (var-get contract-locked)) ERR-CONTRACT-LOCKED)
    (asserts! (or (is-eq caller (get public-partner project)) (is-eq caller (get private-partner project))) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update station revenue
    (map-set charging-stations
      { station-id: station-id }
      (merge station { revenue-generated: (+ (get revenue-generated station) amount) })
    )
    
    ;; Update total contract revenue
    (var-set total-revenue (+ (var-get total-revenue) amount))
    
    (ok true)
  )
)

;; Public function: Distribute revenue
(define-public (distribute-project-revenue (project-id uint) (amount uint))
  (let
    (
      (caller tx-sender)
      (project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
      (sharing (unwrap! (map-get? revenue-sharing { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
      (public-amount (/ (* amount (get public-share-percentage sharing)) u100))
      (private-amount (- amount public-amount))
    )
    (asserts! (not (var-get contract-locked)) ERR-CONTRACT-LOCKED)
    (asserts! (or (is-eq caller (get public-partner project)) (is-eq caller (get private-partner project))) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update revenue sharing records
    (map-set revenue-sharing
      { project-id: project-id }
      (merge sharing { 
        total-distributed: (+ (get total-distributed sharing) amount),
        last-distribution: stacks-block-height
      })
    )
    
    (ok { public-share: public-amount, private-share: private-amount })
  )
)

;; Read-only function: Get stakeholder info
(define-read-only (get-stakeholder (address principal))
  (map-get? stakeholders { address: address })
)

;; Read-only function: Get project info
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

;; Read-only function: Get charging station info
(define-read-only (get-charging-station (station-id uint))
  (map-get? charging-stations { station-id: station-id })
)

;; Read-only function: Get milestone info
(define-read-only (get-milestone (project-id uint) (milestone-type uint))
  (map-get? project-milestones { project-id: project-id, milestone-type: milestone-type })
)

;; Read-only function: Get revenue sharing config
(define-read-only (get-revenue-sharing (project-id uint))
  (map-get? revenue-sharing { project-id: project-id })
)

;; Read-only function: Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-projects: (var-get total-projects),
    total-stations: (var-get total-stations),
    total-revenue: (var-get total-revenue),
    contract-admin: (var-get contract-admin),
    contract-locked: (var-get contract-locked)
  }
)

;; Admin function: Verify stakeholder
(define-public (verify-stakeholder (address principal))
  (let
    (
      (caller tx-sender)
      (stakeholder (unwrap! (map-get? stakeholders { address: address }) ERR-INVALID-STAKEHOLDER))
    )
    (asserts! (is-eq caller (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    
    (map-set stakeholders
      { address: address }
      (merge stakeholder { verified: true })
    )
    
    (ok true)
  )
)

;; Admin function: Lock/unlock contract
(define-public (toggle-contract-lock)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    (var-set contract-locked (not (var-get contract-locked)))
    (ok (var-get contract-locked))
  )
)
