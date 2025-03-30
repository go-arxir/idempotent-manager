-------------------------------- MODULE idempotency_manager --------------------------------
EXTENDS TLC, Integers

Clients == {1, 2}
Resources == {1, 2}
ResourceStates == {"none", "pending", "completed", "failed"}
APIResourceStates == {"none", "created"}

(*--algorithm CreateResource
variables
  db = [x \in Resources |-> "none"];
  api_resources = [y \in Resources |-> "none"];
  response_codes = [z \in Resources |-> "none"];

fair process request \in 1..2
variable
  \* send two requests with a random client, rid.
  client \in Clients;
  rid \in Resources;
  code = "none";
begin
  CaptureResource:
    either
      if db[rid] = "completed" then
        response_codes[rid] := "204";
        goto End;
      elsif db[rid] = "none" then
        db[rid] := "pending";
      else
        skip;
      end if;
    or
      response_codes[rid] := "503";
      goto End;
    end either;
  CreateResource:
    either
      if api_resources[rid] = "created" then
        code := "204";
      else
        api_resources[rid] := "created";
        code := "204";
      end if;
    or
      code := "500";
    end either;
  ConfirmResource:
    either
      if db[rid] = "none" then
        response_codes[rid] := "500";
        goto End;
      elsif db[rid] = "completed" then
        response_codes[rid] := "204";
        goto End;
      elsif code = "204" then
        db[rid] := "completed";
        response_codes[rid] := "204";
        goto End;
      elsif code = "500" then
        db[rid] := "failed";
        response_codes[rid] := "503";
        goto End;
      else
        skip;
      end if;
    or
      response_codes[rid] := "503";
      goto End;
    end either;
  End:
    skip;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "ed915ab3" /\ chksum(tla) = "18e42113")
VARIABLES pc, db, api_resources, response_codes, client, rid, code

vars == << pc, db, api_resources, response_codes, client, rid, code >>

ProcSet == (1..2)

Init == (* Global variables *)
        /\ db = [x \in Resources |-> "none"]
        /\ api_resources = [y \in Resources |-> "none"]
        /\ response_codes = [z \in Resources |-> "none"]
        (* Process request *)
        /\ client \in [1..2 -> Clients]
        /\ rid \in [1..2 -> Resources]
        /\ code = [self \in 1..2 |-> "none"]
        /\ pc = [self \in ProcSet |-> "CaptureResource"]

CaptureResource(self) == /\ pc[self] = "CaptureResource"
                         /\ \/ /\ IF db[rid[self]] = "completed"
                                     THEN /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "204"]
                                          /\ pc' = [pc EXCEPT ![self] = "End"]
                                          /\ db' = db
                                     ELSE /\ IF db[rid[self]] = "none"
                                                THEN /\ db' = [db EXCEPT ![rid[self]] = "pending"]
                                                ELSE /\ TRUE
                                                     /\ db' = db
                                          /\ pc' = [pc EXCEPT ![self] = "CreateResource"]
                                          /\ UNCHANGED response_codes
                            \/ /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "503"]
                               /\ pc' = [pc EXCEPT ![self] = "End"]
                               /\ db' = db
                         /\ UNCHANGED << api_resources, client, rid, code >>

CreateResource(self) == /\ pc[self] = "CreateResource"
                        /\ \/ /\ IF api_resources[rid[self]] = "created"
                                    THEN /\ code' = [code EXCEPT ![self] = "204"]
                                         /\ UNCHANGED api_resources
                                    ELSE /\ api_resources' = [api_resources EXCEPT ![rid[self]] = "created"]
                                         /\ code' = [code EXCEPT ![self] = "204"]
                           \/ /\ code' = [code EXCEPT ![self] = "500"]
                              /\ UNCHANGED api_resources
                        /\ pc' = [pc EXCEPT ![self] = "ConfirmResource"]
                        /\ UNCHANGED << db, response_codes, client, rid >>

ConfirmResource(self) == /\ pc[self] = "ConfirmResource"
                         /\ \/ /\ IF db[rid[self]] = "none"
                                     THEN /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "500"]
                                          /\ pc' = [pc EXCEPT ![self] = "End"]
                                          /\ db' = db
                                     ELSE /\ IF db[rid[self]] = "completed"
                                                THEN /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "204"]
                                                     /\ pc' = [pc EXCEPT ![self] = "End"]
                                                     /\ db' = db
                                                ELSE /\ IF code[self] = "204"
                                                           THEN /\ db' = [db EXCEPT ![rid[self]] = "completed"]
                                                                /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "204"]
                                                                /\ pc' = [pc EXCEPT ![self] = "End"]
                                                           ELSE /\ IF code[self] = "500"
                                                                      THEN /\ db' = [db EXCEPT ![rid[self]] = "failed"]
                                                                           /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "503"]
                                                                           /\ pc' = [pc EXCEPT ![self] = "End"]
                                                                      ELSE /\ TRUE
                                                                           /\ pc' = [pc EXCEPT ![self] = "End"]
                                                                           /\ UNCHANGED << db, 
                                                                                           response_codes >>
                            \/ /\ response_codes' = [response_codes EXCEPT ![rid[self]] = "503"]
                               /\ pc' = [pc EXCEPT ![self] = "End"]
                               /\ db' = db
                         /\ UNCHANGED << api_resources, client, rid, code >>

End(self) == /\ pc[self] = "End"
             /\ TRUE
             /\ pc' = [pc EXCEPT ![self] = "Done"]
             /\ UNCHANGED << db, api_resources, response_codes, client, rid, 
                             code >>

request(self) == CaptureResource(self) \/ CreateResource(self)
                    \/ ConfirmResource(self) \/ End(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == (\E self \in 1..2: request(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in 1..2 : WF_vars(request(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 

ResponseStateInvariant ==
  \A r \in Resources:
    LET c == response_codes[r] IN
      IF c = "204" THEN
        /\ db[r] = "completed"
        /\ api_resources[r] = "created"
      ELSE IF c = "400" THEN
        /\ db[r] = "none"
        /\ api_resources[r] = "none"
      ELSE TRUE

ResponseCodeInvariant ==
  \A r \in Resources:
    response_codes[r] \in {"none", "204", "400", "503"}

TypeInvariant ==
  /\ db \in [Resources -> ResourceStates]
  /\ api_resources \in [Resources -> APIResourceStates]
  /\ ResponseStateInvariant
  /\ ResponseCodeInvariant

EventuallyCompleted ==
  \A id \in Resources:
    (response_codes[id] /= "none" /\ response_codes[id] /= "503") ~> <>[] (db[id] = "completed" \/ db[id] = "failed")

Liveliness ==
  EventuallyCompleted 

=============================================================================
\* Modification History
\* Last modified Sun Mar 30 05:03:10 JST 2025 by nakaiyuu
\* Created Sun Mar 30 05:02:49 JST 2025 by nakaiyuu
