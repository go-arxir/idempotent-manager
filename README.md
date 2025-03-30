# Idempotent Manager

Design patterns and SDKs for distributed transactions ensuring consistency between internal state and external APIs.
Includes techniques for achieving idempotency, chaos engineering validation, and solutions for non-idempotent external APIs.

外部APIとデータベースの整合性を保証するための設計パターン

形式証明 (TLA+) による設計のシーケンスの妥当性は、

## 楽観的アプローチ (Optimistic Approach)

外部APIが冪等である場合に有効なアプローチ

### 特徴

メリット

* 並列可能性
* デッドロックの回避

デメリット

* at least once のリクエストが発生する

### 実装

```mermaid
sequenceDiagram
    participant Client
    participant Service
    participant Database
    participant API as External API

    Client->>+Service: CreateResource {id: "88061582-c66a-4be3-a186-2e6c4fef3cfc", resource: {}}
    Service->>+Database: Begin ReadWriteTransaction
    Service->>+Database: SELECT * FROM resources WHERE id = "88061582-c66a-4be3-a186-2e6c4fef3cfc"
    Database-->>-Service: resource, err
    alt if err != nil && err != NotFound
        Service-->>Client: 500
    else if err != nil && err == NotFound
        Service->>Database: INSERT INTO resources (id, status, resource) VALUES ("88061582-c66a-4be3-a186-2e6c4fef3cfc", "PENDING", {})
    else if err == nil && resource.status = "COMPLETED"|"PERMANENTLY_FAILED"
        Service-->>Client: 200 {status: resource.status}
    else default (err == nil && resource.status = "PENDING"|"FAILED")
        Note right of Service: continue (retry API request)
    end
    Service->>Database: COMMIT
    Database-->>-Service: err
    opt if err != nil
        Service-->>Client: 500
    end

    Service->>+API: POST /resources {"id": "88061582-c66a-4be3-a186-2e6c4fef3cfc", "resource": {}}
    API-->>-Service: code

    Service->>+Database: Begin ReadWriteTransaction
    Service->>+Database: SELECT * FROM resources WHERE id = "88061582-c66a-4be3-a186-2e6c4fef3cfc"
    Database-->>-Service: resource, err
    alt if err != nil
        Service-->>Client: 500
    else if err == nil && resource.status = "COMPLETED"|"PERMANENTLY_FAILED"
        Note right of Service: concurrent process occurred
        Service-->>Client: 200 {status: resource.status}
    end
    alt if code == 200
        Service->>Database: UPDATE resources SET status = "COMPLETED" WHERE id = "88061582-c66a-4be3-a186-2e6c4fef3cfc"
        Service->>Service: response = {status: "COMPLETED"}
    else if code != 200 && isRetryable(code)
        Service->>Database: UPDATE resources SET status = "FAILED" WHERE id = "88061582-c66a-4be3-a186-2e6c4fef3cfc"
        Service->>Service: response = {status: "FAILED"}
    else default (f code != 200 && !isRetryable(code))
        Service->>Database: UPDATE resources SET status = "PERMANENTLY_FAILED" WHERE id = "88061582-c66a-4be3-a186-2e6c4fef3cfc"
        Service->>Service: response = {status: "PERMANENTLY_FAILED"}
    end
    Service->>Database: COMMIT
    Database-->>-Service: err
    opt if err != nil
        Note right of Service: status is stuck in PENDING
        Service-->>Client: 500
    end
    
    Service-->>-Client: 200 response
```

## 悲観的アプローチ (Pessimistic Approach)

外部APIが冪等でない場合に有効なアプローチ

### 特徴

メリット

* exactly once のリクエストが発生する

デメリット

* 悲観的ロックによる並列可能性の低下
* デッドロックの危険性
* 非同期処理の複雑性

### 実装

```mermaid
sequenceDiagram
    participant Client
    participant Service
    participant Database
    participant API as External API
    participant Subscriber
    participant PubSub

    Client->>+Service: CreateResource {id: "88061582-c66a-4be3-a186-2e6c4fef3cfc", resource: {}}
    Service->>+Database: Begin ReadWriteTransaction
    Service->>+Database: SELECT * FROM resources WHERE id = "88061582-c66a-4be3-a186-2e6c4fef3cfc"
    Database-->>-Service: resource, err
    alt if err != nil && err != NotFound
        Service-->>Client: 500
    else if err != nil && err == NotFound
        Service->>Database: INSERT INTO resources (id, status, resource) VALUES ("88061582-c66a-4be3-a186-2e6c4fef3cfc", "PENDING", {})
    else if err == nil && resource.status = "COMPLETED"|"FAILED"
        Service-->>Client: 200 {status: resource.status}
    else default (err == nil && resource.status = "PENDING")
        Note right of Service: abort the process to ensure the exactly one request
        Service-->>Client: 409
    end
    Service->>Database: COMMIT
    Database-->>-Service: err
    opt if err != nil
        Service-->>Client: 500
    end

    Service->>+API: POST /resources {"id": "88061582-c66a-4be3-a186-2e6c4fef3cfc", "resource": {}}
    API-->>-Service: code

    alt if code == 200
        Service->>Service: response = {status: "COMPLETED"}
    else default (code != 200)
        Service->>Service: response = {status: "FAILED"}
    end
    Service-->>-Client: response
    Note right of Service: the internal state must be consistent with the external state

    Service->>PubSub: Publish event = {id: "88061582-c66a-4be3-a186-2e6c4fef3cfc", status: response.status}
    PubSub->>+Subscriber: Invoke Subscriber
    Subscriber->>+Database: Begin ReadWriteTransaction
    Subscriber->>+Database: SELECT * FROM resources WHERE id = event.id
    Database-->>-Subscriber: resource, err
    alt if err != nil
        Subscriber-->>PubSub: NACK
    else if err == nil && resource.status = "COMPLETED"|"FAILED"
        Note right of Subscriber: This occurs since PubSub won't ensure the exactly once delivery
        Subscriber-->>PubSub: ACK
    end
    opt event.status = "FAILED"
        Note over API,Subscriber: the change on the external state might be reflected even if the request is failed
        Subscriber->>+API: GET /resources/{event.id}
        API-->>-Subscriber: status, code
        alt if code == 500
            Subscriber-->>PubSub: NACK
        else default (code != 200)
            Subscriber->>Subscriber: event.status = status
        end
    end
    Subscriber->>Database: UPDATE resources SET status = event.status WHERE id = event.id
    Subscriber->>Subscriber: response = {status: event.status}
    Subscriber->>Database: COMMIT
    Database-->>-Subscriber: err
    opt if err != nil
        Subscriber-->>PubSub: NACK
    end
    Subscriber-->>-PubSub: ACK
```
