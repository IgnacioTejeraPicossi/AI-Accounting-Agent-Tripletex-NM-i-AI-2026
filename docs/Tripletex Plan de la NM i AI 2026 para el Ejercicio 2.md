Plan de la NM i AI 2026 para el Ejercicio 2: Tripletex


Claro. Aquí va un plan operativo para el Ejercicio 2: Tripletex, pensado para que Cursor AI lo implemente y tú lo vayas validando en el sandbox y luego en la competición.
Lo primero importante: para Tripletex sí necesitáis un endpoint HTTPS público; Cloud Run en Google Cloud es la opción recomendada, pero no es obligatorio. La competición acepta cualquier hosting siempre que exponga una URL HTTPS correcta. Aun así, como os han dado documentación y cuenta GCP, Cloud Run en europe-north1 es el camino más directo. 
También conviene tener claro el marco general: NM i AI 2026 tiene tres tareas; Tripletex y Astar Island se envían como endpoint HTTPS, mientras que Object Detection se envía como ZIP. En Tripletex, cada submission recibe una cuenta nueva desde cero, el timeout es de 300 segundos, y el score depende de corrección campo a campo + eficiencia. 
________________________________________
Cursor AI Execution Plan
AI_NM_2026 – Exercise 2: Tripletex AI Accounting Agent
1. Objective
Build a production-ready AI accounting agent that exposes a public HTTPS /solve endpoint.
The validator will send:
•	a natural-language accounting task,
•	optional attached files (PDFs/images),
•	Tripletex proxy credentials (base_url, session_token).
The agent must:
•	understand the task,
•	decide which Tripletex API calls are needed,
•	execute them in the right order,
•	return:
{"status": "completed"}
The validator then checks the resulting account state field-by-field. Efficiency also matters, so unnecessary API calls and avoidable 4xx errors hurt the score. 
________________________________________
2. Recommended strategy
Phase A — Build a safe deterministic baseline
Do not start with a fully autonomous “agent that improvises everything”.
Start with:
•	a FastAPI service,
•	a task router,
•	a Tripletex API client,
•	a small planner that converts prompt → structured intent,
•	a library of deterministic workflows for common tasks.
This is the best path because Tripletex tasks are not just chat tasks; they are structured accounting operations like:
•	create employee,
•	create customer,
•	create product,
•	create invoice,
•	register payment,
•	create project,
•	delete travel expense,
•	enable modules / departments,
•	correct or reverse entries. 
Phase B — Add LLM assistance only where it clearly helps
Use an LLM for:
•	multilingual prompt understanding,
•	extracting entities and values,
•	selecting the workflow,
•	normalizing dates / names / references,
•	extracting data from attachments.
But the final execution should remain tool-driven and deterministic.
Phase C — Optimize efficiency
After correctness works:
•	reduce exploratory GETs,
•	reuse IDs from successful POST responses,
•	validate payloads before sending,
•	do one corrective retry at most.
That matters because score can go above 1.0 when correctness is perfect and efficiency is high. 
________________________________________
3. Key competition constraints to design around
Your endpoint must expose a single HTTPS POST /solve endpoint. The request includes:
•	prompt,
•	optional files,
•	tripletex_credentials.base_url,
•	tripletex_credentials.session_token. 
Authentication to Tripletex is:
•	username: 0
•	password: session_token
using Basic Auth. All calls must go through the provided base_url proxy, not your own hardcoded sandbox URL. 
Important constraints:
•	timeout: 300 seconds
•	endpoint must return HTTP 200 with {"status": "completed"}
•	prompts can come in 7 languages: Norwegian, English, Spanish, Portuguese, Nynorsk, German, French
•	some tasks include PDF or image attachments. 
________________________________________
4. Recommendation about Google Cloud
Yes: use Google Cloud Run unless you already have a better hosted setup.
Why:
•	it is the officially recommended hosting path for endpoint-based tasks,
•	it gives you a public HTTPS URL,
•	deployment is simple with gcloud run deploy --source .,
•	europe-north1 is recommended because it matches validator region,
•	Cloud Shell and Cloud Shell Editor are already prepared for fast setup. 
For AI help inside GCP, your account includes Cloud Shell, Cloud Shell Editor, Gemini Code Assist, Gemini CLI, and access to Vertex AI / Gemini models. 
My recommendation:
•	Cloud Run for hosting,
•	Vertex AI Gemini for prompt parsing if you want managed LLM access,
•	but keep the core execution logic local and deterministic.
________________________________________
5. Recommended architecture
Final recommended baseline architecture
Request -> /solve
       -> request validator
       -> file decoder
       -> prompt interpreter
       -> task classifier
       -> workflow planner
       -> Tripletex API client
       -> verification step
       -> {"status": "completed"}
Components
1.	FastAPI app
Receives /solve requests and orchestrates the whole pipeline.
2.	Request schema layer
Validates incoming JSON and protects against malformed input.
3.	Attachment handler
Decodes base64 files, stores them temporarily, extracts text where possible.
4.	Prompt interpreter
Converts multilingual natural language into a structured action spec.
5.	Task router
Maps prompt to one of a finite set of workflows.
6.	Tripletex client
Handles GET/POST/PUT/DELETE with retries, auth, logging, and response parsing.
7.	Workflow library
One module per task family.
8.	Verifier
Confirms the target entity exists or was updated as intended.
9.	Execution journal
Records what was done for debugging and score optimization.
________________________________________
6. Project structure for Cursor AI
Tell Cursor AI to create this:
tripletex_agent/
├── app/
│   ├── main.py
│   ├── config.py
│   ├── schemas.py
│   ├── dependencies.py
│   │
│   ├── api/
│   │   └── routes.py
│   │
│   ├── core/
│   │   ├── orchestrator.py
│   │   ├── prompt_parser.py
│   │   ├── task_router.py
│   │   ├── planner.py
│   │   ├── verifier.py
│   │   └── execution_context.py
│   │
│   ├── tripletex/
│   │   ├── client.py
│   │   ├── models.py
│   │   ├── errors.py
│   │   ├── search.py
│   │   └── payload_builders.py
│   │
│   ├── workflows/
│   │   ├── base.py
│   │   ├── employees.py
│   │   ├── customers.py
│   │   ├── products.py
│   │   ├── invoices.py
│   │   ├── projects.py
│   │   ├── travel_expenses.py
│   │   ├── departments.py
│   │   └── corrections.py
│   │
│   ├── files/
│   │   ├── decoder.py
│   │   ├── text_extract.py
│   │   └── image_extract.py
│   │
│   ├── llm/
│   │   ├── base.py
│   │   ├── vertex_gemini.py
│   │   └── prompts.py
│   │
│   └── utils/
│       ├── logging.py
│       ├── dates.py
│       ├── language.py
│       └── normalization.py
│
├── tests/
│   ├── test_health.py
│   ├── test_request_schema.py
│   ├── test_tripletex_client.py
│   ├── test_prompt_parser.py
│   └── fixtures/
│
├── scripts/
│   ├── run_local.sh
│   ├── test_sandbox.py
│   └── deploy_cloud_run.sh
│
├── Dockerfile
├── requirements.txt
├── README.md
└── .env.example
________________________________________
7. Implementation plan by work packages
WP1 — Cloud Run deployment baseline
Goal
Get a working HTTPS endpoint live as fast as possible.
Cursor task
Create:
•	FastAPI app,
•	/health,
•	/solve,
•	Dockerfile,
•	requirements,
•	Cloud Run deploy script.
Success criteria
You can deploy to Cloud Run and call:
•	GET /health
•	POST /solve
Cloud Run is the recommended service for Tripletex/Astar Island, and the docs give the exact starter pattern. 
________________________________________
WP2 — Request parsing and schema validation
Goal
Make the service reliable before adding intelligence.
Request schema must support
•	prompt: str
•	files: list
•	tripletex_credentials.base_url
•	tripletex_credentials.session_token
Optional:
•	Bearer token validation if you configure an API key for your endpoint submission. The platform can send Authorization: Bearer <your-api-key>. 
What Cursor should implement
•	Pydantic models,
•	request validation,
•	file metadata validation,
•	secure temp file handling,
•	structured error responses.
________________________________________
WP3 — Tripletex API client
Goal
Build a strong API layer before task logic.
Cursor should implement
A reusable client with methods like:
•	get(path, params=None)
•	post(path, json=None)
•	put(path, json=None)
•	delete(path)
And helpers:
•	list_entities(endpoint, fields=...)
•	find_by_name(endpoint, ...)
•	create_customer(...)
•	create_employee(...)
•	create_product(...)
•	create_invoice(...)
Important Tripletex details
•	list responses are wrapped as {"fullResultSize": N, "values": [...]}
•	fields=* is useful for exploration
•	count and from handle pagination
•	DELETE usually uses ID in the path. 
Best practice
Centralize:
•	auth,
•	timeout,
•	error parsing,
•	logging,
•	retry policy.
________________________________________
WP4 — Prompt understanding
Goal
Turn free text into structured intent.
Recommended baseline
Use the LLM only to return a structured JSON-like intent:
{
  "task_type": "create_employee",
  "language": "es",
  "entities": {
    "employee": {
      "first_name": "Ola",
      "last_name": "Nordmann",
      "email": "ola@example.org"
    }
  },
  "options": {
    "role": "account_administrator"
  }
}
Why
Prompts come in 7 languages, so multilingual parsing is necessary. But execution should not depend on open-ended reasoning.
Recommendation
Prompt parser should extract:
•	task type,
•	entities,
•	fields,
•	required relationships,
•	whether attached files must be read,
•	whether it is create / update / delete / reverse.
________________________________________
WP5 — Workflow library
Goal
Convert structured intent into deterministic API calls.
Implement first these workflows
1.	create_employee
2.	update_employee
3.	create_customer
4.	create_product
5.	create_project
6.	create_invoice
7.	register_payment
8.	create_department
9.	delete_travel_expense
10.	correction_or_reverse_entry
These cover the main task families described in the docs. 
Each workflow should define
•	prerequisites,
•	required fields,
•	search strategy,
•	API call sequence,
•	verification rules,
•	one recovery path for common validation errors.
________________________________________
WP6 — File handling
Goal
Support tasks with attachments.
Docs say
Some tasks include PDF or image files; they arrive as base64 content in files[].
Cursor should implement
•	base64 decode,
•	save temp files,
•	if PDF: extract text,
•	if image: optionally OCR or LLM-based extraction later,
•	pass extracted content into prompt parser.
Practical recommendation
Phase 1:
•	support PDFs with text extraction,
•	store images,
•	include image metadata in the parser input,
•	postpone advanced OCR unless you see a task that truly needs it.
________________________________________
WP7 — Verification layer
Goal
Avoid false “completed” responses.
After each workflow
The agent should:
•	read back the created or modified entity if needed,
•	confirm fields match what was asked,
•	only then return {"status": "completed"}.
This is important because scoring is field-by-field, not based on “attempted action”. 
Efficiency note
Do not over-verify with many GETs. Only verify what is needed.
________________________________________
WP8 — Efficiency optimization
Goal
Improve score once baseline correctness is working.
The docs explicitly recommend
•	plan before calling,
•	avoid trial-and-error,
•	minimize GET calls,
•	reuse IDs from POST responses,
•	read error messages and fix in one retry. 
Cursor should implement
•	no blind search loops,
•	bounded retries,
•	use returned IDs immediately,
•	normalize payloads before sending,
•	one targeted recovery retry on 422 only.
________________________________________
8. Recommended development phases
Phase 1 — “Submission-safe baseline”
Build:
•	FastAPI service,
•	Tripletex client,
•	4–6 core workflows,
•	basic prompt parser,
•	Cloud Run deployment.
Target
A real endpoint that can solve a subset of tasks correctly and safely.
________________________________________
Phase 2 — “Competitive baseline”
Add:
•	multilingual normalization,
•	attachment support,
•	more workflows,
•	verification,
•	logging and replay.
Target
Good correctness across common task families.
________________________________________
Phase 3 — “Leaderboard optimization”
Add:
•	better workflow selection,
•	one-pass planning,
•	targeted error recovery,
•	reduced GET usage,
•	richer structured extraction from prompts/files.
Target
Improve efficiency bonus and reduce failure rate.
________________________________________
9. Concrete prompts for Cursor AI
Prompt 1 — Master setup
We are building a production-ready FastAPI service for AI_NM_2026 Task 2: Tripletex AI Accounting Agent.

Goal:
Expose a public HTTPS POST /solve endpoint that receives:
- prompt
- optional files
- tripletex_credentials.base_url
- tripletex_credentials.session_token

The service must understand the task, call the Tripletex v2 API through the provided proxy URL using Basic Auth username=0 and password=session_token, complete the accounting task, verify the result, and return {"status":"completed"}.

Competition facts:
- timeout 300 seconds
- fresh Tripletex account per submission
- prompts can be in Norwegian, English, Spanish, Portuguese, Nynorsk, German, French
- some tasks include PDF or image attachments
- score depends on field-by-field correctness and efficiency
- avoid unnecessary GET calls and avoidable 4xx errors

Technical direction:
- FastAPI
- deterministic workflow engine
- LLM-assisted prompt parsing only
- modular Tripletex client
- Cloud Run deployment
- production-quality Python, clean architecture, clear logging

Please create maintainable code, not a hackathon script.
Prompt 2 — Main FastAPI service
Create a clean FastAPI application with:
- GET /health returning {"status":"ok"}
- POST /solve
- Pydantic request/response schemas
- structured logging
- request validation for prompt, files, and tripletex_credentials
- placeholder orchestrator call inside /solve

Use an app/ package structure and production-style code organization.
Prompt 3 — Tripletex API client
Create a reusable Tripletex API client module.

Requirements:
- initialize with base_url and session_token
- use requests or httpx
- Basic Auth username "0", password=session_token
- support get, post, put, delete
- parse Tripletex list responses with "values"
- expose helper methods for common resource lookups
- strong error handling with custom exceptions
- concise logging for each API call
- timeout-safe defaults

Design the module so workflows can reuse it without duplicating HTTP logic.
Prompt 4 — Prompt parser
Create a prompt parsing module that converts multilingual accounting prompts into a structured intent object.

The parser should output:
- task_type
- language
- action (create/update/delete/reverse/register)
- extracted entities
- extracted fields
- dependencies/prerequisites
- confidence score

Design it so it can work first with rule-based heuristics and later with an LLM backend such as Vertex AI Gemini.
Prompt 5 — Workflow engine
Create a workflow engine for Tripletex tasks.

Requirements:
- define a base workflow interface
- create initial workflow modules for:
  create_employee
  create_customer
  create_product
  create_project
  create_invoice
  delete_travel_expense
- each workflow should:
  validate inputs
  search only when necessary
  create/update/delete entities via the Tripletex client
  return execution metadata
  support a verification step

Keep the design easy to extend with more workflows later.
Prompt 6 — File handling
Create file handling utilities for the /solve endpoint.

Requirements:
- decode base64 attachments from the request
- save them safely to a temporary directory
- support PDF text extraction
- support image attachment storage for future OCR/parsing
- return structured metadata and extracted text summary
- keep implementation robust and simple
Prompt 7 — Cloud Run deployment
Create deployment artifacts for Google Cloud Run:
- Dockerfile
- requirements.txt
- .dockerignore
- deploy_cloud_run.sh

Requirements:
- Python 3.11
- run FastAPI with uvicorn on port 8080
- suitable for gcloud run deploy --source .
- include environment variable support for optional API key and optional Vertex AI configuration
________________________________________
10. File structure for the first implementation milestone
For the first milestone, keep it tighter:
tripletex_agent/
├── app/
│   ├── main.py
│   ├── schemas.py
│   ├── config.py
│   ├── orchestrator.py
│   ├── prompt_parser.py
│   ├── task_router.py
│   ├── verifier.py
│   ├── tripletex_client.py
│   ├── file_handler.py
│   └── workflows/
│       ├── __init__.py
│       ├── employees.py
│       ├── customers.py
│       ├── invoices.py
│       └── products.py
├── tests/
├── Dockerfile
├── requirements.txt
├── README.md
└── scripts/
    └── deploy_cloud_run.sh
________________________________________
11. First coding milestone
What you should ask Cursor to produce first
1.	main.py with /health and /solve
2.	schemas.py
3.	tripletex_client.py
4.	prompt_parser.py
5.	task_router.py
6.	one workflow: create_employee
7.	Dockerfile + deploy script
Why
This gets you to a real end-to-end path:
•	receive prompt,
•	parse,
•	call API,
•	complete one task family,
•	deploy.
That is the equivalent of your first valid ZIP in the detection task.
________________________________________
12. First competitive milestone
After that, add these workflows:
•	create_customer
•	create_product
•	create_project
•	create_invoice
•	delete_travel_expense
These correspond well to the examples and main categories in the docs.
________________________________________
13. Suggested execution logic inside /solve
Recommended orchestration:
1.	Validate request
2.	Decode files
3.	Build execution context
4.	Parse prompt into structured intent
5.	Route to workflow
6.	Execute workflow using Tripletex client
7.	Verify result
8.	Return {"status":"completed"}
If an unsupported task is detected:
•	log clearly,
•	optionally run a fallback generic planner,
•	but do not build the whole system around a vague fallback first.
________________________________________
14. Practical notes about the sandbox account
The persistent Tripletex sandbox is useful for learning the data model and testing manually, but competition submissions run against a fresh new account each time through the provided proxy URL. So your logic must not rely on old persistent data. 
That means Cursor should implement workflows assuming:
•	no entities exist yet unless created in this run,
•	prerequisites may need to be created first,
•	order matters.
This is especially relevant for invoices, payments, and project/customer links. 
________________________________________
15. Recommended GCP setup
Use your GCP account like this:
•	Cloud Shell / Cloud Shell Editor for coding and deployment
•	Cloud Run for the public endpoint
•	Vertex AI Gemini only if you want LLM parsing from inside the endpoint
•	Cloud Storage only if later you need persistent logs or artifacts.
First deploy command target
Use europe-north1, optionally --min-instances 1 during active testing to reduce cold starts. That is explicitly recommended in the docs. 
________________________________________
16. Main risks and mitigations
Risk 1 — Too much autonomy, too little control
Mitigation:
Start with deterministic workflows, not a free-form agent.
Risk 2 — Wasting score on avoidable 4xx errors
Mitigation:
Validate payloads locally, search only when needed, one targeted retry.
Risk 3 — Slow endpoint
Mitigation:
Bound API calls, avoid loops, keep prompt parsing concise, timeout guard.
Risk 4 — Multilingual parsing errors
Mitigation:
Force parser output into a structured schema and normalize field names.
Risk 5 — Attachment parsing complexity
Mitigation:
Start with PDF text extraction and simple file handling first.
________________________________________
17. My recommendation in one sentence
Build a Cloud Run FastAPI service with a deterministic Tripletex workflow engine, use LLMs only for structured prompt extraction, and optimize efficiency only after the first end-to-end submission works.
Si quieres, en el siguiente mensaje te preparo el Pack 2 para Cursor, con:
•	prompts aún más precisos por archivo,
•	main.py base,
•	tripletex_client.py base,
•	y un primer Dockerfile + script de deploy listos para copiar y pegar.

Ignacio: Si, gracias, preparame el Pack 2 para Cursor, con:
prompts aún más precisos por archivo,
main.py base,
tripletex_client.py base,
y un primer Dockerfile + script de deploy listos para copiar y pegar.
....
Perfecto. Aquí tienes el Pack 2 para Cursor: más concreto, más ejecutable y pensado para que lleguéis rápido a un endpoint válido en Cloud Run para Tripletex.
La base documental encaja con esta estrategia: Tripletex se entrega como endpoint HTTPS /solve, autenticando contra el base_url recibido con Basic Auth (username="0", password=session_token), con timeout de 300 segundos. Cloud Run en europe-north1 es la vía recomendada, y los prompts pueden venir en 7 idiomas, además de incluir PDFs o imágenes. 
1. Enfoque recomendado para esta primera versión
No intentéis hacer desde el principio un “agente general mágico”.
Haced primero esto:
•	FastAPI + /health + /solve
•	validación fuerte del request
•	cliente Tripletex robusto
•	parser simple de intención
•	router de workflows
•	2 o 3 workflows deterministas
•	despliegue a Cloud Run
Eso os da una primera submission real. Luego ampliáis. Las tareas típicas incluyen empleados, clientes, productos, facturas, proyectos, gastos de viaje y correcciones; además, el score depende de corrección + eficiencia, así que conviene evitar búsquedas y errores 4xx innecesarios. 
________________________________________
2. Estructura mínima recomendada
tripletex_agent/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── schemas.py
│   ├── config.py
│   ├── orchestrator.py
│   ├── prompt_parser.py
│   ├── task_router.py
│   ├── file_handler.py
│   ├── verifier.py
│   ├── tripletex_client.py
│   └── workflows/
│       ├── __init__.py
│       ├── base.py
│       ├── create_employee.py
│       ├── create_customer.py
│       └── create_product.py
├── tests/
│   └── test_smoke.py
├── requirements.txt
├── Dockerfile
├── .dockerignore
├── deploy_cloud_run.sh
└── README.md
________________________________________
3. Orden exacto de implementación en Cursor
1.	schemas.py
2.	tripletex_client.py
3.	file_handler.py
4.	prompt_parser.py
5.	task_router.py
6.	workflows/base.py
7.	workflows/create_employee.py
8.	orchestrator.py
9.	main.py
10.	Dockerfile
11.	deploy_cloud_run.sh
________________________________________
4. Prompt maestro para Cursor
Pega esto primero en Cursor:
We are building a production-ready FastAPI service for AI_NM_2026 Task 2: Tripletex AI Accounting Agent.

Competition contract:
- Public HTTPS endpoint
- POST /solve
- Must accept JSON with:
  - prompt
  - optional files
  - tripletex_credentials.base_url
  - tripletex_credentials.session_token
- Must authenticate to Tripletex with Basic Auth:
  - username: "0"
  - password: session_token
- Must use the provided base_url proxy, not a hardcoded Tripletex URL
- Must return HTTP 200 with {"status":"completed"}
- Timeout: 300 seconds
- Prompts may be in Norwegian, English, Spanish, Portuguese, Nynorsk, German, French
- Some tasks may include base64 PDF or image attachments
- Score depends on correctness and efficiency, so avoid unnecessary API calls and avoidable 4xx errors

Technical direction:
- FastAPI
- modular code under app/
- deterministic workflows first
- simple prompt parsing first, extensible to Vertex AI Gemini later
- Cloud Run deployment
- robust request validation
- concise structured logging
- production-style Python 3.11

Important design rules:
- keep the implementation maintainable
- avoid over-engineering
- prefer explicit workflows over a vague autonomous agent
- write code that is easy to extend with more workflows
________________________________________
5. Prompt por archivo para Cursor
schemas.py
Create app/schemas.py using Pydantic.

Define request/response models for the Tripletex competition endpoint.

Models required:
- SolveFile
  - filename: str
  - content_base64: str
  - mime_type: str
- TripletexCredentials
  - base_url: str
  - session_token: str
- SolveRequest
  - prompt: str
  - files: list[SolveFile] = []
  - tripletex_credentials: TripletexCredentials
- SolveResponse
  - status: str

Also define internal models:
- ParsedIntent
  - task_type: str
  - action: str
  - language: str | None
  - entities: dict
  - fields: dict
  - confidence: float
- ExecutionResult
  - success: bool
  - workflow_name: str
  - created_ids: dict
  - notes: list[str]
  - verification: dict

Add reasonable validation:
- prompt cannot be empty
- base_url must be a valid URL
- session_token cannot be empty
- filename cannot be empty
- content_base64 cannot be empty
tripletex_client.py
Create app/tripletex_client.py.

Build a reusable Tripletex API client with:
- constructor(base_url: str, session_token: str, timeout: float = 20.0)
- Basic Auth username "0", password=session_token
- methods:
  - get(path, params=None)
  - post(path, json_body=None, params=None)
  - put(path, json_body=None, params=None)
  - delete(path, params=None)
- helper methods:
  - list_values(path, params=None)
  - get_first_match(path, params=None)
  - create_customer(...)
  - create_employee(...)
  - create_product(...)
  - find_customer_by_name(name)
  - find_employee_by_email(email)
  - find_product_by_name(name)

Requirements:
- use requests.Session
- robust URL joining
- parse Tripletex list responses with "values"
- parse single-object responses with "value" when present
- raise custom exceptions on non-2xx responses
- include concise logging
- keep code easy to extend

Also create:
- TripletexApiError
- TripletexValidationError
- TripletexNotFoundError
file_handler.py
Create app/file_handler.py.

Requirements:
- decode base64 attachments safely
- store them in a temporary directory
- return structured metadata for each file:
  - filename
  - mime_type
  - path
  - size_bytes
  - extracted_text
- support PDF text extraction in a simple, robust way
- if PDF text extraction is unavailable, return empty extracted_text without crashing
- support images by saving them only for now
- keep implementation simple and production-friendly
prompt_parser.py
Create app/prompt_parser.py.

Purpose:
Convert multilingual accounting prompts into a simple structured ParsedIntent.

Version 1 should be mostly rule-based and deterministic.

Requirements:
- detect probable language with lightweight heuristics
- infer task_type and action from prompt text
- extract common entities and fields using regex/simple rules
- support at least:
  - create_employee
  - create_customer
  - create_product
- extract:
  - names
  - email addresses
  - phone numbers if present
  - role hints if present
- return ParsedIntent

Design it so a future Vertex AI Gemini backend can replace or enhance the parser later.
task_router.py
Create app/task_router.py.

Purpose:
Map ParsedIntent to a workflow class.

Requirements:
- implement a simple registry
- route at least:
  - create_employee
  - create_customer
  - create_product
- raise a clear UnsupportedTaskError when no workflow matches
- keep the API simple:
  - get_workflow(intent) -> workflow instance/class
workflows/base.py
Create app/workflows/base.py.

Define a BaseWorkflow class with:
- name attribute
- validate_intent(intent)
- execute(intent, client, context)
- verify(intent, client, execution_result)

Use abc.ABC for abstract methods.
Return structured ExecutionResult objects.
Keep it simple and deterministic.
workflows/create_employee.py
Create app/workflows/create_employee.py.

Implement a deterministic workflow for employee creation.

Requirements:
- validate required fields
- if email is present, first try to find an existing employee by email
- if employee already exists, do not create duplicates
- otherwise POST to /employee
- support fields if present:
  - firstName
  - lastName
  - email
  - mobileNumber or phone
- if the prompt implies a role, keep it as a note for now unless the exact API field is known
- verify by reading back the employee if necessary
- return ExecutionResult
- avoid unnecessary GET calls
orchestrator.py
Create app/orchestrator.py.

Purpose:
Run the end-to-end flow for /solve.

Flow:
1. decode files
2. parse prompt into intent
3. create Tripletex client
4. route workflow
5. execute workflow
6. verify result
7. return execution result

Requirements:
- structured logging
- clear error handling
- keep the public interface simple:
  - solve_task(request_model) -> ExecutionResult
main.py
Create app/main.py.

Requirements:
- FastAPI app
- GET /health returns {"status":"ok"}
- POST /solve
- validate incoming request using SolveRequest
- call solve_task from orchestrator
- on success return {"status":"completed"}
- if unsupported task, return HTTP 400 with a concise message
- if Tripletex API validation fails, return HTTP 400
- on unexpected errors, return HTTP 500
- keep logs concise and useful
- suitable for Cloud Run on port 8080 with uvicorn
________________________________________
6. main.py base listo para copiar y pegar
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from app.orchestrator import solve_task
from app.schemas import SolveRequest, SolveResponse
from app.task_router import UnsupportedTaskError
from app.tripletex_client import TripletexApiError, TripletexValidationError

app = FastAPI(title="Tripletex Agent", version="0.1.0")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/solve", response_model=SolveResponse)
async def solve(request: SolveRequest):
    try:
        result = solve_task(request)
        if not result.success:
            raise HTTPException(status_code=400, detail="Task execution failed")
        return SolveResponse(status="completed")

    except UnsupportedTaskError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    except TripletexValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    except TripletexApiError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {exc}") from exc
________________________________________
7. tripletex_client.py base listo para copiar y pegar
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.parse import urljoin

import requests


class TripletexApiError(Exception):
    pass


class TripletexValidationError(TripletexApiError):
    pass


class TripletexNotFoundError(TripletexApiError):
    pass


@dataclass
class TripletexClient:
    base_url: str
    session_token: str
    timeout: float = 20.0

    def __post_init__(self) -> None:
        self.base_url = self.base_url.rstrip("/") + "/"
        self.session = requests.Session()
        self.session.auth = ("0", self.session_token)
        self.session.headers.update(
            {
                "Accept": "application/json",
                "Content-Type": "application/json",
            }
        )

    def _build_url(self, path: str) -> str:
        return urljoin(self.base_url, path.lstrip("/"))

    def _handle_response(self, response: requests.Response) -> Any:
        if response.status_code == 404:
            raise TripletexNotFoundError(f"Tripletex resource not found: {response.text}")

        if response.status_code in (400, 401, 403, 422):
            raise TripletexValidationError(
                f"Tripletex validation/auth error {response.status_code}: {response.text}"
            )

        if not response.ok:
            raise TripletexApiError(
                f"Tripletex API error {response.status_code}: {response.text}"
            )

        if not response.content:
            return None

        try:
            data = response.json()
        except ValueError as exc:
            raise TripletexApiError("Tripletex returned non-JSON response") from exc

        if isinstance(data, dict) and "value" in data:
            return data["value"]
        return data

    def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        response = self.session.get(
            self._build_url(path),
            params=params,
            timeout=self.timeout,
        )
        return self._handle_response(response)

    def post(
        self,
        path: str,
        json_body: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Any:
        response = self.session.post(
            self._build_url(path),
            json=json_body,
            params=params,
            timeout=self.timeout,
        )
        return self._handle_response(response)

    def put(
        self,
        path: str,
        json_body: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Any:
        response = self.session.put(
            self._build_url(path),
            json=json_body,
            params=params,
            timeout=self.timeout,
        )
        return self._handle_response(response)

    def delete(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        response = self.session.delete(
            self._build_url(path),
            params=params,
            timeout=self.timeout,
        )
        return self._handle_response(response)

    def list_values(self, path: str, params: Optional[Dict[str, Any]] = None) -> list[dict]:
        data = self.get(path, params=params)
        if isinstance(data, dict) and "values" in data:
            return data["values"]
        if isinstance(data, list):
            return data
        return []

    def get_first_match(self, path: str, params: Optional[Dict[str, Any]] = None) -> Optional[dict]:
        values = self.list_values(path, params=params)
        return values[0] if values else None

    def find_customer_by_name(self, name: str) -> Optional[dict]:
        return self.get_first_match(
            "/customer",
            params={"name": name, "fields": "id,name,email", "count": 10},
        )

    def find_employee_by_email(self, email: str) -> Optional[dict]:
        values = self.list_values(
            "/employee",
            params={"fields": "id,firstName,lastName,email,mobileNumber", "count": 100},
        )
        for item in values:
            if str(item.get("email", "")).strip().lower() == email.strip().lower():
                return item
        return None

    def find_product_by_name(self, name: str) -> Optional[dict]:
        return self.get_first_match(
            "/product",
            params={"name": name, "fields": "id,name,productNumber", "count": 10},
        )

    def create_customer(
        self,
        name: str,
        email: Optional[str] = None,
        is_customer: bool = True,
    ) -> dict:
        payload: Dict[str, Any] = {
            "name": name,
            "isCustomer": is_customer,
        }
        if email:
            payload["email"] = email
        return self.post("/customer", json_body=payload)

    def create_employee(
        self,
        first_name: str,
        last_name: str,
        email: Optional[str] = None,
        mobile_number: Optional[str] = None,
    ) -> dict:
        payload: Dict[str, Any] = {
            "firstName": first_name,
            "lastName": last_name,
        }
        if email:
            payload["email"] = email
        if mobile_number:
            payload["mobileNumber"] = mobile_number
        return self.post("/employee", json_body=payload)

    def create_product(
        self,
        name: str,
        product_number: Optional[str] = None,
    ) -> dict:
        payload: Dict[str, Any] = {"name": name}
        if product_number:
            payload["productNumber"] = product_number
        return self.post("/product", json_body=payload)
________________________________________
8. schemas.py base
from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, HttpUrl, field_validator


class SolveFile(BaseModel):
    filename: str
    content_base64: str
    mime_type: str

    @field_validator("filename", "content_base64", "mime_type")
    @classmethod
    def not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Field cannot be empty")
        return value


class TripletexCredentials(BaseModel):
    base_url: HttpUrl
    session_token: str

    @field_validator("session_token")
    @classmethod
    def token_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("session_token cannot be empty")
        return value


class SolveRequest(BaseModel):
    prompt: str
    files: list[SolveFile] = Field(default_factory=list)
    tripletex_credentials: TripletexCredentials

    @field_validator("prompt")
    @classmethod
    def prompt_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("prompt cannot be empty")
        return value


class SolveResponse(BaseModel):
    status: str = "completed"


class ParsedIntent(BaseModel):
    task_type: str
    action: str
    language: str | None = None
    entities: dict[str, Any] = Field(default_factory=dict)
    fields: dict[str, Any] = Field(default_factory=dict)
    confidence: float = 0.0


class ExecutionResult(BaseModel):
    success: bool
    workflow_name: str
    created_ids: dict[str, Any] = Field(default_factory=dict)
    notes: list[str] = Field(default_factory=list)
    verification: dict[str, Any] = Field(default_factory=dict)
________________________________________
9. prompt_parser.py base
import re

from app.schemas import ParsedIntent


EMAIL_RE = re.compile(r"[\w\.-]+@[\w\.-]+\.\w+")
PHONE_RE = re.compile(r"(\+\d{1,3}\s?)?[\d\s-]{6,}")


def detect_language(prompt: str) -> str | None:
    text = prompt.lower()
    if any(word in text for word in ["opprett", "ansatt", "kunde"]):
        return "nb"
    if any(word in text for word in ["crear", "empleado", "cliente", "producto"]):
        return "es"
    if any(word in text for word in ["create", "employee", "customer", "product"]):
        return "en"
    if any(word in text for word in ["criar", "funcionário", "cliente", "produto"]):
        return "pt"
    if any(word in text for word in ["mitarbeiter", "kunde", "produkt", "erstellen"]):
        return "de"
    if any(word in text for word in ["employé", "client", "produit", "créer"]):
        return "fr"
    return None


def parse_prompt(prompt: str) -> ParsedIntent:
    text = prompt.strip()
    lower = text.lower()
    language = detect_language(text)

    email_match = EMAIL_RE.search(text)
    phone_match = PHONE_RE.search(text)

    if any(word in lower for word in ["employee", "empleado", "ansatt", "employé", "mitarbeiter"]):
        first_name, last_name = _extract_person_name(text)
        return ParsedIntent(
            task_type="create_employee",
            action="create",
            language=language,
            entities={"employee": {"first_name": first_name, "last_name": last_name}},
            fields={
                "email": email_match.group(0) if email_match else None,
                "phone": phone_match.group(0).strip() if phone_match else None,
            },
            confidence=0.75,
        )

    if any(word in lower for word in ["customer", "cliente", "kunde", "client"]):
        name = _extract_quoted_or_tail_name(text)
        return ParsedIntent(
            task_type="create_customer",
            action="create",
            language=language,
            entities={"customer": {"name": name}},
            fields={"email": email_match.group(0) if email_match else None},
            confidence=0.70,
        )

    if any(word in lower for word in ["product", "producto", "produkt", "produit"]):
        name = _extract_quoted_or_tail_name(text)
        return ParsedIntent(
            task_type="create_product",
            action="create",
            language=language,
            entities={"product": {"name": name}},
            fields={},
            confidence=0.65,
        )

    return ParsedIntent(
        task_type="unsupported",
        action="unknown",
        language=language,
        entities={},
        fields={},
        confidence=0.10,
    )


def _extract_person_name(text: str) -> tuple[str, str]:
    tokens = re.findall(r"[A-ZÁÉÍÓÚÄÖÜÅÆØÑ][a-záéíóúäöüåæøñ'-]+", text)
    if len(tokens) >= 2:
        return tokens[0], tokens[1]
    if len(tokens) == 1:
        return tokens[0], ""
    return "Unknown", "Unknown"


def _extract_quoted_or_tail_name(text: str) -> str:
    quoted = re.findall(r'"([^"]+)"', text)
    if quoted:
        return quoted[0].strip()
    return text.strip()
________________________________________
10. task_router.py base
from app.schemas import ParsedIntent
from app.workflows.create_customer import CreateCustomerWorkflow
from app.workflows.create_employee import CreateEmployeeWorkflow
from app.workflows.create_product import CreateProductWorkflow


class UnsupportedTaskError(Exception):
    pass


def get_workflow(intent: ParsedIntent):
    if intent.task_type == "create_employee":
        return CreateEmployeeWorkflow()
    if intent.task_type == "create_customer":
        return CreateCustomerWorkflow()
    if intent.task_type == "create_product":
        return CreateProductWorkflow()
    raise UnsupportedTaskError(f"Unsupported task type: {intent.task_type}")
________________________________________
11. workflows/base.py base
from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient


class BaseWorkflow(ABC):
    name = "base"

    @abstractmethod
    def validate_intent(self, intent: ParsedIntent) -> None:
        raise NotImplementedError

    @abstractmethod
    def execute(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        context: dict,
    ) -> ExecutionResult:
        raise NotImplementedError

    @abstractmethod
    def verify(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        execution_result: ExecutionResult,
    ) -> dict:
        raise NotImplementedError
________________________________________
12. workflows/create_employee.py base
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateEmployeeWorkflow(BaseWorkflow):
    name = "create_employee"

    def validate_intent(self, intent: ParsedIntent) -> None:
        employee = intent.entities.get("employee", {})
        first_name = employee.get("first_name")
        last_name = employee.get("last_name")
        if not first_name or not last_name:
            raise TripletexValidationError("Employee first_name and last_name are required")

    def execute(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        context: dict,
    ) -> ExecutionResult:
        self.validate_intent(intent)

        employee = intent.entities["employee"]
        email = intent.fields.get("email")
        phone = intent.fields.get("phone")

        if email:
            existing = client.find_employee_by_email(email)
            if existing:
                return ExecutionResult(
                    success=True,
                    workflow_name=self.name,
                    created_ids={"employee_id": existing.get("id")},
                    notes=["Employee already existed; skipped duplicate creation"],
                    verification={"existing": True},
                )

        created = client.create_employee(
            first_name=employee["first_name"],
            last_name=employee["last_name"],
            email=email,
            mobile_number=phone,
        )

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"employee_id": created.get("id")},
            notes=[],
            verification={},
        )

    def verify(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        execution_result: ExecutionResult,
    ) -> dict:
        return {"verified": True}
________________________________________
13. workflows/create_customer.py base
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateCustomerWorkflow(BaseWorkflow):
    name = "create_customer"

    def validate_intent(self, intent: ParsedIntent) -> None:
        customer = intent.entities.get("customer", {})
        if not customer.get("name"):
            raise TripletexValidationError("Customer name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        customer_name = intent.entities["customer"]["name"]
        email = intent.fields.get("email")

        existing = client.find_customer_by_name(customer_name)
        if existing:
            return ExecutionResult(
                success=True,
                workflow_name=self.name,
                created_ids={"customer_id": existing.get("id")},
                notes=["Customer already existed; skipped duplicate creation"],
                verification={"existing": True},
            )

        created = client.create_customer(name=customer_name, email=email)

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"customer_id": created.get("id")},
            notes=[],
            verification={},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return {"verified": True}
________________________________________
14. workflows/create_product.py base
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateProductWorkflow(BaseWorkflow):
    name = "create_product"

    def validate_intent(self, intent: ParsedIntent) -> None:
        product = intent.entities.get("product", {})
        if not product.get("name"):
            raise TripletexValidationError("Product name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        product_name = intent.entities["product"]["name"]
        existing = client.find_product_by_name(product_name)
        if existing:
            return ExecutionResult(
                success=True,
                workflow_name=self.name,
                created_ids={"product_id": existing.get("id")},
                notes=["Product already existed; skipped duplicate creation"],
                verification={"existing": True},
            )

        created = client.create_product(name=product_name)

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"product_id": created.get("id")},
            notes=[],
            verification={},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return {"verified": True}
________________________________________
15. file_handler.py base
import base64
import tempfile
from pathlib import Path

from app.schemas import SolveFile


def decode_files(files: list[SolveFile]) -> list[dict]:
    output = []
    temp_dir = Path(tempfile.mkdtemp(prefix="tripletex_files_"))

    for f in files:
        raw = base64.b64decode(f.content_base64)
        target = temp_dir / f.filename
        target.write_bytes(raw)

        extracted_text = ""
        if f.mime_type == "application/pdf":
            extracted_text = _extract_pdf_text_safe(target)

        output.append(
            {
                "filename": f.filename,
                "mime_type": f.mime_type,
                "path": str(target),
                "size_bytes": len(raw),
                "extracted_text": extracted_text,
            }
        )

    return output


def _extract_pdf_text_safe(path: Path) -> str:
    try:
        from pypdf import PdfReader

        reader = PdfReader(str(path))
        return "\n".join(page.extract_text() or "" for page in reader.pages).strip()
    except Exception:
        return ""
________________________________________
16. orchestrator.py base
from app.file_handler import decode_files
from app.prompt_parser import parse_prompt
from app.schemas import ExecutionResult, SolveRequest
from app.task_router import get_workflow
from app.tripletex_client import TripletexClient


def solve_task(request: SolveRequest) -> ExecutionResult:
    decoded_files = decode_files(request.files)

    prompt = request.prompt
    if decoded_files:
        extracted_text = "\n\n".join(
            item["extracted_text"] for item in decoded_files if item.get("extracted_text")
        )
        if extracted_text:
            prompt = f"{prompt}\n\nAttached file text:\n{extracted_text}"

    intent = parse_prompt(prompt)

    client = TripletexClient(
        base_url=str(request.tripletex_credentials.base_url),
        session_token=request.tripletex_credentials.session_token,
    )

    workflow = get_workflow(intent)
    context = {"files": decoded_files}

    result = workflow.execute(intent, client, context)
    result.verification = workflow.verify(intent, client, result)
    return result
________________________________________
17. requirements.txt inicial
fastapi==0.115.8
uvicorn[standard]==0.34.0
requests==2.32.3
pydantic==2.10.6
pypdf==5.3.0
________________________________________
18. Dockerfile listo para copiar y pegar
Cloud Run acepta contenedor HTTP en puerto 8080, y la doc propone justo este patrón con Python 3.11 y uvicorn. 
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
________________________________________
19. .dockerignore
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
.venv/
venv/
.env
.git/
.gitignore
tests/
.pytest_cache/
________________________________________
20. deploy_cloud_run.sh listo para copiar y pegar
Cloud Run en europe-north1 está recomendado para bajar latencia respecto al validador; además podéis usar --min-instances 1 durante pruebas activas para evitar cold starts. 
#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-tripletex-agent}"
REGION="${REGION:-europe-north1}"
MEMORY="${MEMORY:-1Gi}"
TIMEOUT="${TIMEOUT:-300}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"

echo "Deploying ${SERVICE_NAME} to Cloud Run in ${REGION}..."

gcloud run deploy "${SERVICE_NAME}" \
  --source . \
  --region "${REGION}" \
  --allow-unauthenticated \
  --memory "${MEMORY}" \
  --timeout "${TIMEOUT}" \
  --min-instances "${MIN_INSTANCES}"

echo "Deployment finished."
echo "Health check example:"
echo "  curl https://YOUR-SERVICE-URL/health"
Dale permisos antes de usarlo:
chmod +x deploy_cloud_run.sh
________________________________________
21. Prompt para que Cursor te complete tests mínimos
Create a very small smoke-test setup.

Add:
- tests/test_smoke.py
- one test for GET /health
- one test for POST /solve with a mocked orchestrator
- keep tests simple and runnable with pytest

Do not overcomplicate.
________________________________________
22. Prompt para la siguiente iteración útil
Cuando esta base funcione, pega esto:
Now extend the baseline Tripletex agent with:
1. better multilingual parsing
2. create_invoice workflow
3. create_project workflow
4. delete_travel_expense workflow
5. verification that minimizes unnecessary GET calls
6. improved field extraction from PDF text

Keep the architecture unchanged and extend the existing modules cleanly.
________________________________________
23. Qué deberíais probar primero
Primero, local:
•	GET /health
•	POST /solve con un prompt sencillo de create employee
•	contra vuestro sandbox manual de Tripletex
Después, Cloud Run:
•	desplegar
•	probar /health
•	probar /solve con curl
•	revisar logs
La documentación deja claro que el sandbox manual sirve para aprender el modelo y probar, pero la competición usa una cuenta nueva en cada submission, así que el código no debe depender de datos persistentes previos. 
________________________________________
24. Prioridad real de workflows
Yo empezaría así:
1.	create_employee
2.	create_customer
3.	create_product
4.	create_project
5.	create_invoice
6.	delete_travel_expense
Porque reflejan bastante bien los patrones que salen en los ejemplos oficiales. 
________________________________________
25. Recomendación final
Primero montad esta base y sacad un endpoint vivo en Cloud Run. Luego hacéis una segunda vuelta de Cursor para mejorar parser, workflows y eficiencia.
Cuando quieras, te preparo el Pack 3, con:
•	curl de prueba para /solve,
•	un README.md mínimo,
•	y una versión más lista de create_invoice.py y create_project.py.

Ignacio:me puedes preparar el Pack 3, con:
•	curl de prueba para /solve,
•	un README.md mínimo,
•	y una versión más lista de create_invoice.py y create_project.py.


create_project.py. 
Tenkte i 7s
Sí. Aquí tienes el Pack 3 para Cursor, listo para copiar y pegar.
Incluye:
•	curl de prueba para /solve
•	un README.md mínimo
•	una versión más seria de create_invoice.py
•	una versión más seria de create_project.py
Voy a mantenerlo en la misma línea del Pack 2:
•	simple,
•	extendible,
•	pensado para una primera submission funcional,
•	sin volverlo demasiado inteligente todavía.
________________________________________
1. curl de prueba para /solve
Caso 1: crear empleado
curl -X POST "https://YOUR-CLOUD-RUN-URL/solve" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create an employee named Ola Nordmann with email ola.nordmann@example.com and phone +47 12345678",
    "files": [],
    "tripletex_credentials": {
      "base_url": "https://tripletex-proxy.example.com/v2",
      "session_token": "YOUR_SESSION_TOKEN"
    }
  }'
Caso 2: crear cliente
curl -X POST "https://YOUR-CLOUD-RUN-URL/solve" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create a customer named Nordic Bakery AS with email post@nordicbakery.no",
    "files": [],
    "tripletex_credentials": {
      "base_url": "https://tripletex-proxy.example.com/v2",
      "session_token": "YOUR_SESSION_TOKEN"
    }
  }'
Caso 3: crear producto
curl -X POST "https://YOUR-CLOUD-RUN-URL/solve" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create a product called Consulting Hour",
    "files": [],
    "tripletex_credentials": {
      "base_url": "https://tripletex-proxy.example.com/v2",
      "session_token": "YOUR_SESSION_TOKEN"
    }
  }'
Caso 4: crear proyecto
curl -X POST "https://YOUR-CLOUD-RUN-URL/solve" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create a project named Migration Project for customer Nordic Bakery AS",
    "files": [],
    "tripletex_credentials": {
      "base_url": "https://tripletex-proxy.example.com/v2",
      "session_token": "YOUR_SESSION_TOKEN"
    }
  }'
Caso 5: crear factura
curl -X POST "https://YOUR-CLOUD-RUN-URL/solve" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create an invoice for customer Nordic Bakery AS with one line for Consulting Hour, quantity 2, unit price 1500",
    "files": [],
    "tripletex_credentials": {
      "base_url": "https://tripletex-proxy.example.com/v2",
      "session_token": "YOUR_SESSION_TOKEN"
    }
  }'
Caso 6: health check
curl "https://YOUR-CLOUD-RUN-URL/health"
________________________________________
2. Prompt para Cursor: mejorar parser para project + invoice
Pégale esto a Cursor antes de añadir los workflows:
Extend the current prompt parser so it can also detect and extract intents for:
- create_project
- create_invoice

For create_project, extract:
- project name
- customer name if present
- employee name if present

For create_invoice, extract:
- customer name
- invoice date if present
- due date if present
- one or more line items if present
- for each line item: product name, description if present, quantity, unit price

Keep the parser deterministic and simple, with regex and rule-based extraction only.
Return ParsedIntent in the same existing schema.
Do not redesign the architecture.
________________________________________
3. README.md mínimo
# Tripletex Agent

Minimal FastAPI service for AI_NM_2026 Task 2: Tripletex.

## What it does

This service exposes:

- `GET /health`
- `POST /solve`

The `/solve` endpoint receives:
- a natural-language accounting prompt,
- optional attached files,
- Tripletex proxy credentials:
  - `base_url`
  - `session_token`

The service parses the prompt, chooses a workflow, calls the Tripletex API, verifies the result, and returns:

```json
{"status": "completed"}
Project structure
app/
  main.py
  schemas.py
  orchestrator.py
  prompt_parser.py
  task_router.py
  file_handler.py
  tripletex_client.py
  workflows/
Local development
Create and activate a virtual environment, then install dependencies:
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
Run locally:
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
Test health endpoint:
curl http://localhost:8080/health
Example /solve request
curl -X POST "http://localhost:8080/solve" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create an employee named Ola Nordmann with email ola.nordmann@example.com",
    "files": [],
    "tripletex_credentials": {
      "base_url": "https://tripletex-proxy.example.com/v2",
      "session_token": "YOUR_SESSION_TOKEN"
    }
  }'
Docker
Build image:
docker build -t tripletex-agent .
Run container locally:
docker run -p 8080:8080 tripletex-agent
Deploy to Cloud Run
chmod +x deploy_cloud_run.sh
./deploy_cloud_run.sh
Current workflows
Implemented or partially implemented:
•	create_employee
•	create_customer
•	create_product
•	create_project
•	create_invoice
Notes
•	The service should use the provided Tripletex base_url proxy for all API calls.
•	Authentication is Basic Auth with username 0 and password equal to session_token.
•	Workflows should stay deterministic and efficient.
•	Avoid unnecessary GET calls and duplicate entity creation.

---

# 4. Prompt para Cursor: crear `create_project.py`

```text
Create app/workflows/create_project.py.

Requirements:
- workflow name: create_project
- validate that project name exists
- if customer name is present, look up the customer first
- avoid duplicate project creation when a project with the same name already exists
- create the project using the Tripletex client
- if a customer is found, link the project to that customer if supported by the payload
- return ExecutionResult with created project ID
- verification should be lightweight and deterministic
- avoid unnecessary GET calls
- keep code consistent with the existing workflow style

Also extend tripletex_client.py with helper methods:
- find_project_by_name(name)
- create_project(name, customer_id=None)
________________________________________
5. Prompt para Cursor: crear create_invoice.py
Create app/workflows/create_invoice.py.

Requirements:
- workflow name: create_invoice
- validate that customer name exists
- validate that at least one invoice line exists
- look up the customer first
- for each invoice line:
  - if a product name is present, try to find the product
  - build a line payload with quantity and unit price if present
- create the invoice using the Tripletex client
- return ExecutionResult with created invoice ID
- keep verification lightweight
- avoid unnecessary GET calls
- if the exact invoice API payload is uncertain, keep the structure modular and clearly isolated in helper methods

Also extend tripletex_client.py with helper methods:
- create_invoice(customer_id, invoice_date=None, due_date=None, lines=None)
- optionally find_order_or_invoice_draft helpers if useful

Keep the code deterministic and production-style.
________________________________________
6. create_project.py base más lista
Guárdalo en app/workflows/create_project.py.
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import (
    TripletexClient,
    TripletexNotFoundError,
    TripletexValidationError,
)
from app.workflows.base import BaseWorkflow


class CreateProjectWorkflow(BaseWorkflow):
    name = "create_project"

    def validate_intent(self, intent: ParsedIntent) -> None:
        project = intent.entities.get("project", {})
        project_name = project.get("name")
        if not project_name or not str(project_name).strip():
            raise TripletexValidationError("Project name is required")

    def execute(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        context: dict,
    ) -> ExecutionResult:
        self.validate_intent(intent)

        project = intent.entities.get("project", {})
        project_name = str(project.get("name", "")).strip()
        customer_name = intent.fields.get("customer_name")

        existing = client.find_project_by_name(project_name)
        if existing:
            return ExecutionResult(
                success=True,
                workflow_name=self.name,
                created_ids={"project_id": existing.get("id")},
                notes=["Project already existed; skipped duplicate creation"],
                verification={"existing": True},
            )

        customer_id = None
        if customer_name:
            customer = client.find_customer_by_name(customer_name)
            if customer:
                customer_id = customer.get("id")
            else:
                raise TripletexNotFoundError(
                    f"Customer not found for project creation: {customer_name}"
                )

        created = client.create_project(
            name=project_name,
            customer_id=customer_id,
        )

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"project_id": created.get("id")},
            notes=[],
            verification={},
        )

    def verify(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        execution_result: ExecutionResult,
    ) -> dict:
        project_id = execution_result.created_ids.get("project_id")
        if not project_id:
            return {"verified": False}

        try:
            project = client.get(f"/project/{project_id}", params={"fields": "id,name"})
            return {
                "verified": True,
                "project_id": project.get("id"),
                "name": project.get("name"),
            }
        except Exception:
            return {"verified": False}
________________________________________
7. create_invoice.py base más lista
Guárdalo en app/workflows/create_invoice.py.
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import (
    TripletexClient,
    TripletexNotFoundError,
    TripletexValidationError,
)
from app.workflows.base import BaseWorkflow


class CreateInvoiceWorkflow(BaseWorkflow):
    name = "create_invoice"

    def validate_intent(self, intent: ParsedIntent) -> None:
        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])

        if not customer_name or not str(customer_name).strip():
            raise TripletexValidationError("Invoice customer_name is required")

        if not lines or not isinstance(lines, list):
            raise TripletexValidationError("At least one invoice line is required")

    def execute(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        context: dict,
    ) -> ExecutionResult:
        self.validate_intent(intent)

        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        invoice_date = invoice.get("invoice_date") or intent.fields.get("invoice_date")
        due_date = invoice.get("due_date") or intent.fields.get("due_date")
        raw_lines = invoice.get("lines", [])

        customer = client.find_customer_by_name(customer_name)
        if not customer:
            raise TripletexNotFoundError(f"Customer not found for invoice: {customer_name}")

        customer_id = customer.get("id")
        lines = []

        for raw_line in raw_lines:
            lines.append(self._build_invoice_line(raw_line, client))

        created = client.create_invoice(
            customer_id=customer_id,
            invoice_date=invoice_date,
            due_date=due_date,
            lines=lines,
        )

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"invoice_id": created.get("id")},
            notes=[],
            verification={},
        )

    def verify(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        execution_result: ExecutionResult,
    ) -> dict:
        invoice_id = execution_result.created_ids.get("invoice_id")
        if not invoice_id:
            return {"verified": False}

        try:
            invoice = client.get(f"/invoice/{invoice_id}", params={"fields": "id,invoiceDate,customer"})
            return {
                "verified": True,
                "invoice_id": invoice.get("id"),
            }
        except Exception:
            return {"verified": False}

    def _build_invoice_line(self, raw_line: dict, client: TripletexClient) -> dict:
        if not isinstance(raw_line, dict):
            raise TripletexValidationError("Invoice line must be an object")

        product_name = raw_line.get("product_name")
        description = raw_line.get("description")
        quantity = raw_line.get("quantity", 1)
        unit_price = raw_line.get("unit_price")

        line_payload = {
            "count": quantity,
        }

        if description:
            line_payload["description"] = description

        if unit_price is not None:
            line_payload["unitPrice"] = unit_price

        if product_name:
            product = client.find_product_by_name(product_name)
            if not product:
                raise TripletexNotFoundError(
                    f"Product not found for invoice line: {product_name}"
                )
            line_payload["product"] = {"id": product.get("id")}

        return line_payload
________________________________________
8. Extensión recomendada para tripletex_client.py
Añade estos métodos dentro de TripletexClient:
    def find_project_by_name(self, name: str) -> Optional[dict]:
        return self.get_first_match(
            "/project",
            params={"name": name, "fields": "id,name", "count": 10},
        )

    def create_project(
        self,
        name: str,
        customer_id: Optional[int] = None,
    ) -> dict:
        payload: Dict[str, Any] = {"name": name}
        if customer_id is not None:
            payload["customer"] = {"id": customer_id}
        return self.post("/project", json_body=payload)

    def create_invoice(
        self,
        customer_id: int,
        invoice_date: Optional[str] = None,
        due_date: Optional[str] = None,
        lines: Optional[list[dict]] = None,
    ) -> dict:
        payload: Dict[str, Any] = {
            "customer": {"id": customer_id},
            "orderLines": lines or [],
        }
        if invoice_date:
            payload["invoiceDate"] = invoice_date
        if due_date:
            payload["dueDate"] = due_date
        return self.post("/invoice", json_body=payload)
________________________________________
9. Extensión recomendada para task_router.py
Añade imports y rutas:
from app.workflows.create_invoice import CreateInvoiceWorkflow
from app.workflows.create_project import CreateProjectWorkflow
Y dentro de get_workflow(intent):
    if intent.task_type == "create_project":
        return CreateProjectWorkflow()
    if intent.task_type == "create_invoice":
        return CreateInvoiceWorkflow()
________________________________________
10. Extensión recomendada para prompt_parser.py
Para que todo conecte, dile a Cursor que añada soporte mínimo para project e invoice con este prompt:
Extend app/prompt_parser.py to support:
- create_project
- create_invoice

Rules:
- create_project:
  detect keywords like project/proyecto/prosjekt/projet
  extract project name
  extract customer name after phrases like "for customer", "for client", "para cliente"
- create_invoice:
  detect keywords like invoice/factura/faktura
  extract customer name
  extract one simple line item if present:
    product name
    quantity
    unit price
  store result inside entities["invoice"]["lines"]

Keep the implementation rule-based and minimal.
Do not redesign the ParsedIntent schema.
________________________________________
11. Ejemplo esperado de intent para project
ParsedIntent(
    task_type="create_project",
    action="create",
    language="en",
    entities={
        "project": {
            "name": "Migration Project"
        }
    },
    fields={
        "customer_name": "Nordic Bakery AS"
    },
    confidence=0.72,
)
________________________________________
12. Ejemplo esperado de intent para invoice
ParsedIntent(
    task_type="create_invoice",
    action="create",
    language="en",
    entities={
        "invoice": {
            "customer_name": "Nordic Bakery AS",
            "lines": [
                {
                    "product_name": "Consulting Hour",
                    "quantity": 2,
                    "unit_price": 1500
                }
            ]
        }
    },
    fields={},
    confidence=0.70,
)
________________________________________
13. Prompt final para Cursor: cerrar la iteración
Now integrate the new project and invoice workflows into the existing Tripletex agent.

Tasks:
1. add create_project.py
2. add create_invoice.py
3. extend tripletex_client.py with project and invoice helper methods
4. extend task_router.py
5. extend prompt_parser.py with minimal rule-based support
6. keep everything consistent with the existing architecture
7. do not redesign the codebase

After implementation, summarize:
- which endpoints and payload assumptions were used
- where the code may still need Tripletex-specific payload adjustment
- what should be tested first against the sandbox
________________________________________
14. Qué probar justo después
Haz estas pruebas en este orden:
1.	/health
2.	create_employee
3.	create_customer
4.	create_product
5.	create_project
6.	create_invoice
No empieces probando invoice antes de customer/product/project, porque invoice suele depender de más relaciones y es donde más fácil es que falle el payload.
________________________________________
15. Recomendación práctica
La parte más delicada aquí no es FastAPI ni Cloud Run. Es ajustar exactamente los payloads Tripletex reales para project e invoice. Así que lo más inteligente es que Cursor implemente esta base, y después vosotros la validéis rápidamente contra el sandbox manual para corregir:
•	nombres exactos de campos,
•	path exacto de endpoints,
•	estructura de líneas de factura.
En el siguiente paso te puedo preparar un Pack 4 de hardening, con:
•	tests básicos con pytest,
•	logging útil para Cloud Run,
•	y una estrategia de “retry seguro” para errores 400/422.


Ignacio: Si, gracias, preparame un Pack 4 de hardening, con:
tests básicos con pytest,
logging útil para Cloud Run,
y una estrategia de “retry seguro” para errores 400/422.

Perfecto. Aquí tienes el Pack 4 de hardening para Cursor, enfocado en tres cosas:
•	tests básicos con pytest
•	logging útil para Cloud Run
•	estrategia de retry seguro para errores 400/422
La idea es endurecer la base sin complicar demasiado la arquitectura.
________________________________________
1. Objetivo del Pack 4
En esta iteración no buscamos añadir más features. Buscamos que el agente sea:
•	más estable
•	más observable
•	más seguro frente a fallos evitables
•	y más fácil de depurar cuando falle en sandbox o en competición
________________________________________
2. Qué debe implementar Cursor en esta fase
Prioridad 1
Añadir tests de humo y tests unitarios ligeros para:
•	/health
•	/solve
•	parser
•	router
•	cliente Tripletex con mocks
•	workflow de create employee / customer / product
Prioridad 2
Añadir logging estructurado y útil para Cloud Run:
•	request id
•	workflow seleccionado
•	número de llamadas Tripletex
•	tiempo total
•	errores resumidos
Prioridad 3
Añadir retry seguro:
•	no retry ciego
•	solo retry acotado y específico
•	principalmente para errores 400/422 donde una corrección local sea razonable
________________________________________
3. Estructura recomendada tras hardening
tripletex_agent/
├── app/
│   ├── main.py
│   ├── schemas.py
│   ├── orchestrator.py
│   ├── prompt_parser.py
│   ├── task_router.py
│   ├── file_handler.py
│   ├── tripletex_client.py
│   ├── retry_policy.py
│   ├── logging_utils.py
│   ├── context.py
│   └── workflows/
│       ├── base.py
│       ├── create_employee.py
│       ├── create_customer.py
│       ├── create_product.py
│       ├── create_project.py
│       └── create_invoice.py
├── tests/
│   ├── conftest.py
│   ├── test_health.py
│   ├── test_solve.py
│   ├── test_prompt_parser.py
│   ├── test_task_router.py
│   ├── test_tripletex_client.py
│   ├── test_create_employee_workflow.py
│   ├── test_create_customer_workflow.py
│   └── test_create_product_workflow.py
├── requirements.txt
├── Dockerfile
└── README.md
________________________________________
4. Prompt maestro para Cursor
Pega esto primero:
Harden the current Tripletex FastAPI service for production-style reliability.

Goals:
1. add basic pytest coverage
2. add structured logging suitable for Google Cloud Run
3. add a safe retry strategy for selected 400/422 validation failures
4. keep the architecture simple and deterministic
5. do not redesign the codebase

Requirements:
- add tests for /health, /solve, parser, router, Tripletex client, and the main workflows
- add structured logging with request_id, workflow_name, elapsed_ms, api_call_count, and concise error summaries
- add safe retry logic only for clearly correctable validation errors
- avoid generic retry loops
- keep the code clean, modular, and easy to debug
________________________________________
5. Tests básicos con pytest
requirements.txt añadir
pytest==8.3.5
httpx==0.28.1
Si ya tenéis fastapi, el TestClient os sirve bien.
________________________________________
Prompt para tests/conftest.py
Create tests/conftest.py.

Requirements:
- provide a FastAPI TestClient fixture for the app
- provide simple reusable sample payload fixtures for:
  - create_employee
  - create_customer
  - create_product
- keep fixtures minimal and readable
tests/conftest.py
import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def employee_payload():
    return {
        "prompt": "Create an employee named Ola Nordmann with email ola.nordmann@example.com and phone +47 12345678",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }


@pytest.fixture
def customer_payload():
    return {
        "prompt": "Create a customer named Nordic Bakery AS with email post@nordicbakery.no",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }


@pytest.fixture
def product_payload():
    return {
        "prompt": "Create a product called Consulting Hour",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }
________________________________________
Prompt para tests/test_health.py
Create tests/test_health.py with one simple test:
- GET /health returns HTTP 200 and {"status":"ok"}
tests/test_health.py
def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
________________________________________
Prompt para tests/test_solve.py
Create tests/test_solve.py.

Requirements:
- mock app.orchestrator.solve_task
- test successful /solve returns HTTP 200 and {"status":"completed"}
- test unsupported task returns HTTP 400
- keep tests concise
tests/test_solve.py
from unittest.mock import patch

from app.schemas import ExecutionResult
from app.task_router import UnsupportedTaskError


def test_solve_success(client, employee_payload):
    with patch("app.main.solve_task") as mock_solve:
        mock_solve.return_value = ExecutionResult(
            success=True,
            workflow_name="create_employee",
            created_ids={"employee_id": 123},
            notes=[],
            verification={"verified": True},
        )

        response = client.post("/solve", json=employee_payload)
        assert response.status_code == 200
        assert response.json() == {"status": "completed"}


def test_solve_unsupported_task(client, employee_payload):
    with patch("app.main.solve_task") as mock_solve:
        mock_solve.side_effect = UnsupportedTaskError("Unsupported task type: unsupported")

        response = client.post("/solve", json=employee_payload)
        assert response.status_code == 400
        assert "Unsupported task type" in response.json()["detail"]
________________________________________
Prompt para tests/test_prompt_parser.py
Create tests/test_prompt_parser.py.

Requirements:
- test create_employee prompt parsing
- test create_customer prompt parsing
- test create_product prompt parsing
- verify task_type and key extracted fields
- keep tests deterministic
tests/test_prompt_parser.py
from app.prompt_parser import parse_prompt


def test_parse_employee():
    intent = parse_prompt(
        "Create an employee named Ola Nordmann with email ola.nordmann@example.com and phone +47 12345678"
    )
    assert intent.task_type == "create_employee"
    assert intent.entities["employee"]["first_name"] == "Ola"
    assert intent.entities["employee"]["last_name"] == "Nordmann"
    assert intent.fields["email"] == "ola.nordmann@example.com"


def test_parse_customer():
    intent = parse_prompt(
        'Create a customer named "Nordic Bakery AS" with email post@nordicbakery.no'
    )
    assert intent.task_type == "create_customer"
    assert "customer" in intent.entities


def test_parse_product():
    intent = parse_prompt("Create a product called Consulting Hour")
    assert intent.task_type == "create_product"
    assert "product" in intent.entities
________________________________________
Prompt para tests/test_task_router.py
Create tests/test_task_router.py.

Requirements:
- test create_employee routes correctly
- test create_customer routes correctly
- test unsupported task raises UnsupportedTaskError
tests/test_task_router.py
import pytest

from app.schemas import ParsedIntent
from app.task_router import UnsupportedTaskError, get_workflow


def test_route_employee():
    intent = ParsedIntent(task_type="create_employee", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_employee"


def test_route_customer():
    intent = ParsedIntent(task_type="create_customer", action="create")
    workflow = get_workflow(intent)
    assert workflow.name == "create_customer"


def test_route_unsupported():
    intent = ParsedIntent(task_type="unsupported", action="unknown")
    with pytest.raises(UnsupportedTaskError):
        get_workflow(intent)
________________________________________
Prompt para tests/test_tripletex_client.py
Create tests/test_tripletex_client.py.

Requirements:
- mock requests.Session methods
- test response parsing for:
  - {"value": {...}}
  - {"values": [...]}
- test validation error handling for HTTP 400
- keep tests lightweight
tests/test_tripletex_client.py
from unittest.mock import Mock

import pytest
import requests

from app.tripletex_client import TripletexClient, TripletexValidationError


def make_response(status_code=200, json_data=None, text=""):
    response = Mock(spec=requests.Response)
    response.status_code = status_code
    response.ok = 200 <= status_code < 300
    response.text = text
    response.content = b'{}' if json_data is not None else b""
    response.json.return_value = json_data
    return response


def test_handle_value_response():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    response = make_response(json_data={"value": {"id": 1, "name": "Test"}})
    data = client._handle_response(response)
    assert data["id"] == 1


def test_list_values_response():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    client.get = Mock(return_value={"values": [{"id": 1}, {"id": 2}]})
    values = client.list_values("/customer")
    assert len(values) == 2


def test_validation_error():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    response = make_response(status_code=400, json_data={"message": "bad request"}, text="bad request")
    with pytest.raises(TripletexValidationError):
        client._handle_response(response)
________________________________________
Prompt para tests de workflows
Create workflow tests for create_employee, create_customer, and create_product.

Requirements:
- mock the Tripletex client methods
- test duplicate detection path
- test create path
- assert returned ExecutionResult fields
- keep tests small and readable
tests/test_create_employee_workflow.py
from unittest.mock import Mock

from app.schemas import ParsedIntent
from app.workflows.create_employee import CreateEmployeeWorkflow


def test_create_employee_existing():
    workflow = CreateEmployeeWorkflow()
    client = Mock()
    client.find_employee_by_email.return_value = {"id": 55, "email": "ola@example.com"}

    intent = ParsedIntent(
        task_type="create_employee",
        action="create",
        entities={"employee": {"first_name": "Ola", "last_name": "Nordmann"}},
        fields={"email": "ola@example.com"},
    )

    result = workflow.execute(intent, client, context={})
    assert result.success is True
    assert result.created_ids["employee_id"] == 55
    assert "already existed" in result.notes[0]


def test_create_employee_new():
    workflow = CreateEmployeeWorkflow()
    client = Mock()
    client.find_employee_by_email.return_value = None
    client.create_employee.return_value = {"id": 77}

    intent = ParsedIntent(
        task_type="create_employee",
        action="create",
        entities={"employee": {"first_name": "Ola", "last_name": "Nordmann"}},
        fields={"email": "ola@example.com", "phone": "+47 12345678"},
    )

    result = workflow.execute(intent, client, context={})
    assert result.success is True
    assert result.created_ids["employee_id"] == 77
tests/test_create_customer_workflow.py
from unittest.mock import Mock

from app.schemas import ParsedIntent
from app.workflows.create_customer import CreateCustomerWorkflow


def test_create_customer_existing():
    workflow = CreateCustomerWorkflow()
    client = Mock()
    client.find_customer_by_name.return_value = {"id": 5, "name": "Nordic Bakery AS"}

    intent = ParsedIntent(
        task_type="create_customer",
        action="create",
        entities={"customer": {"name": "Nordic Bakery AS"}},
        fields={"email": "post@nordicbakery.no"},
    )

    result = workflow.execute(intent, client, context={})
    assert result.success is True
    assert result.created_ids["customer_id"] == 5


def test_create_customer_new():
    workflow = CreateCustomerWorkflow()
    client = Mock()
    client.find_customer_by_name.return_value = None
    client.create_customer.return_value = {"id": 9}

    intent = ParsedIntent(
        task_type="create_customer",
        action="create",
        entities={"customer": {"name": "Nordic Bakery AS"}},
        fields={"email": "post@nordicbakery.no"},
    )

    result = workflow.execute(intent, client, context={})
    assert result.success is True
    assert result.created_ids["customer_id"] == 9
tests/test_create_product_workflow.py
from unittest.mock import Mock

from app.schemas import ParsedIntent
from app.workflows.create_product import CreateProductWorkflow


def test_create_product_existing():
    workflow = CreateProductWorkflow()
    client = Mock()
    client.find_product_by_name.return_value = {"id": 11, "name": "Consulting Hour"}

    intent = ParsedIntent(
        task_type="create_product",
        action="create",
        entities={"product": {"name": "Consulting Hour"}},
        fields={},
    )

    result = workflow.execute(intent, client, context={})
    assert result.success is True
    assert result.created_ids["product_id"] == 11


def test_create_product_new():
    workflow = CreateProductWorkflow()
    client = Mock()
    client.find_product_by_name.return_value = None
    client.create_product.return_value = {"id": 22}

    intent = ParsedIntent(
        task_type="create_product",
        action="create",
        entities={"product": {"name": "Consulting Hour"}},
        fields={},
    )

    result = workflow.execute(intent, client, context={})
    assert result.success is True
    assert result.created_ids["product_id"] == 22
________________________________________
6. Logging útil para Cloud Run
En Cloud Run os conviene logging estructurado y corto. No queréis ruido, queréis contexto.
Qué loggear siempre
Por request:
•	request_id
•	path
•	workflow_name
•	prompt_length
•	files_count
•	elapsed_ms
•	tripletex_api_calls
•	result
•	error_type si falla
Por llamada Tripletex:
•	método
•	endpoint
•	status_code
•	elapsed_ms
Nunca logguéis:
•	session_token
•	contenido completo de archivos
•	prompts completos si incluyen datos sensibles
________________________________________
Prompt para logging_utils.py
Create app/logging_utils.py.

Requirements:
- configure structured JSON-style logging for Cloud Run
- provide:
  - get_logger(name)
  - log_event(logger, event_name, **fields)
- include timestamp, level, logger name, and custom fields
- keep logs concise and safe
- do not log secrets such as session_token
app/logging_utils.py
import json
import logging
import sys
from datetime import datetime, timezone
from typing import Any


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.propagate = False
    return logger


def log_event(logger: logging.Logger, event_name: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event_name,
        **_sanitize_fields(fields),
    }
    logger.info(json.dumps(payload, ensure_ascii=False))


def _sanitize_fields(fields: dict[str, Any]) -> dict[str, Any]:
    redacted_keys = {"session_token", "authorization", "password"}
    clean = {}
    for key, value in fields.items():
        if key.lower() in redacted_keys:
            clean[key] = "***REDACTED***"
        else:
            clean[key] = value
    return clean
________________________________________
Prompt para añadir contexto por request
Create app/context.py.

Requirements:
- define a lightweight execution context object
- include:
  - request_id
  - start_time
  - api_call_count
  - workflow_name
- provide helper method to compute elapsed_ms
- keep it very simple
app/context.py
import time
import uuid
from dataclasses import dataclass, field


@dataclass
class ExecutionContext:
    request_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    start_time: float = field(default_factory=time.perf_counter)
    api_call_count: int = 0
    workflow_name: str = ""

    def elapsed_ms(self) -> int:
        return int((time.perf_counter() - self.start_time) * 1000)
________________________________________
Cómo integrarlo en orchestrator.py
Pídele esto a Cursor:
Update app/orchestrator.py to add structured logging and execution context.

Requirements:
- create ExecutionContext per request
- log solve_started, intent_parsed, workflow_selected, workflow_completed, and solve_failed
- include request_id, workflow_name, elapsed_ms, files_count, and api_call_count
- do not log secrets
- keep logging concise
Versión endurecida de orchestrator.py
from app.context import ExecutionContext
from app.file_handler import decode_files
from app.logging_utils import get_logger, log_event
from app.prompt_parser import parse_prompt
from app.schemas import ExecutionResult, SolveRequest
from app.task_router import get_workflow
from app.tripletex_client import TripletexClient

logger = get_logger("tripletex.orchestrator")


def solve_task(request: SolveRequest) -> ExecutionResult:
    ctx = ExecutionContext()

    log_event(
        logger,
        "solve_started",
        request_id=ctx.request_id,
        files_count=len(request.files),
        prompt_length=len(request.prompt),
    )

    decoded_files = decode_files(request.files)

    prompt = request.prompt
    if decoded_files:
        extracted_text = "\n\n".join(
            item["extracted_text"] for item in decoded_files if item.get("extracted_text")
        )
        if extracted_text:
            prompt = f"{prompt}\n\nAttached file text:\n{extracted_text}"

    intent = parse_prompt(prompt)
    log_event(
        logger,
        "intent_parsed",
        request_id=ctx.request_id,
        task_type=intent.task_type,
        action=intent.action,
        confidence=intent.confidence,
        elapsed_ms=ctx.elapsed_ms(),
    )

    client = TripletexClient(
        base_url=str(request.tripletex_credentials.base_url),
        session_token=request.tripletex_credentials.session_token,
        execution_context=ctx,
    )

    workflow = get_workflow(intent)
    ctx.workflow_name = workflow.name

    log_event(
        logger,
        "workflow_selected",
        request_id=ctx.request_id,
        workflow_name=ctx.workflow_name,
        elapsed_ms=ctx.elapsed_ms(),
    )

    context = {"files": decoded_files, "execution_context": ctx}
    result = workflow.execute(intent, client, context)
    result.verification = workflow.verify(intent, client, result)

    log_event(
        logger,
        "workflow_completed",
        request_id=ctx.request_id,
        workflow_name=ctx.workflow_name,
        success=result.success,
        api_call_count=ctx.api_call_count,
        elapsed_ms=ctx.elapsed_ms(),
    )

    return result
________________________________________
7. Logging dentro de tripletex_client.py
Prompt para Cursor
Update app/tripletex_client.py to support structured logging and API call counting.

Requirements:
- accept optional execution_context in constructor
- increment api_call_count on each HTTP call
- log method, endpoint, status_code, and elapsed_ms
- do not log session_token or full response bodies
- keep changes minimal
Cambios recomendados en TripletexClient
Añade imports:
import time
from typing import Any, Dict, Optional
from app.logging_utils import get_logger, log_event
Añade logger de módulo:
logger = get_logger("tripletex.client")
Actualiza dataclass:
from app.context import ExecutionContext

@dataclass
class TripletexClient:
    base_url: str
    session_token: str
    timeout: float = 20.0
    execution_context: Optional[ExecutionContext] = None
Y endurece get/post/put/delete con una función central:
    def _request(
        self,
        method: str,
        path: str,
        params: Optional[Dict[str, Any]] = None,
        json_body: Optional[Dict[str, Any]] = None,
    ) -> Any:
        url = self._build_url(path)
        start = time.perf_counter()

        response = self.session.request(
            method=method,
            url=url,
            params=params,
            json=json_body,
            timeout=self.timeout,
        )

        elapsed_ms = int((time.perf_counter() - start) * 1000)

        if self.execution_context:
            self.execution_context.api_call_count += 1
            request_id = self.execution_context.request_id
        else:
            request_id = None

        log_event(
            logger,
            "tripletex_api_call",
            request_id=request_id,
            method=method,
            path=path,
            status_code=response.status_code,
            elapsed_ms=elapsed_ms,
        )

        return self._handle_response(response)

    def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        return self._request("GET", path, params=params)

    def post(
        self,
        path: str,
        json_body: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Any:
        return self._request("POST", path, params=params, json_body=json_body)

    def put(
        self,
        path: str,
        json_body: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Any:
        return self._request("PUT", path, params=params, json_body=json_body)

    def delete(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        return self._request("DELETE", path, params=params)
________________________________________
8. Estrategia de retry seguro para 400/422
Aquí hay que ser muy disciplinados.
Regla principal
Nunca hagáis retry genérico de un 400/422.
Solo reintentad si:
•	el error es claramente de payload corregible,
•	la corrección es local, determinista y segura,
•	y solo hacéis un único retry.
Ejemplos razonables de retry
•	eliminar campos vacíos "" o None
•	renombrar internamente phone -> mobileNumber
•	convertir cantidad "2" a 2
•	convertir precio "1500" a 1500.0
•	eliminar una línea opcional inválida si el resto sigue siendo válido
•	normalizar fecha a formato ISO simple si venía en forma evidente
Ejemplos no razonables
•	probar 5 payloads distintos
•	buscar entidades repetidamente hasta acertar
•	cambiar customer/product arbitrariamente
•	recrear el workflow entero varias veces
________________________________________
Prompt para retry_policy.py
Create app/retry_policy.py.

Requirements:
- implement a safe retry helper for Tripletex validation failures
- only allow one retry
- retry only when the payload can be deterministically normalized
- provide:
  - normalize_payload_for_retry(path, payload)
  - should_retry_validation_error(error_message, payload)
- keep logic conservative
- do not create retry loops
app/retry_policy.py
from __future__ import annotations

from copy import deepcopy
from typing import Any


def should_retry_validation_error(error_message: str, payload: dict[str, Any] | None) -> bool:
    if not payload:
        return False

    message = (error_message or "").lower()

    retry_hints = [
        "validation",
        "invalid",
        "unknown field",
        "cannot deserialize",
        "expected",
        "bad request",
    ]
    return any(hint in message for hint in retry_hints)


def normalize_payload_for_retry(path: str, payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if not payload:
        return payload

    cleaned = _remove_empty_values(deepcopy(payload))

    if path == "/employee":
        cleaned = _normalize_employee_payload(cleaned)

    if path == "/invoice":
        cleaned = _normalize_invoice_payload(cleaned)

    return cleaned


def _remove_empty_values(value: Any) -> Any:
    if isinstance(value, dict):
        result = {}
        for k, v in value.items():
            cleaned = _remove_empty_values(v)
            if cleaned in ("", None, [], {}):
                continue
            result[k] = cleaned
        return result

    if isinstance(value, list):
        result = []
        for item in value:
            cleaned = _remove_empty_values(item)
            if cleaned in ("", None, [], {}):
                continue
            result.append(cleaned)
        return result

    return value


def _normalize_employee_payload(payload: dict[str, Any]) -> dict[str, Any]:
    if "phone" in payload and "mobileNumber" not in payload:
        payload["mobileNumber"] = payload.pop("phone")
    return payload


def _normalize_invoice_payload(payload: dict[str, Any]) -> dict[str, Any]:
    lines = payload.get("orderLines")
    if isinstance(lines, list):
        for line in lines:
            if "count" in line and isinstance(line["count"], str):
                try:
                    line["count"] = int(line["count"])
                except ValueError:
                    pass
            if "unitPrice" in line and isinstance(line["unitPrice"], str):
                try:
                    line["unitPrice"] = float(line["unitPrice"])
                except ValueError:
                    pass
    return payload
________________________________________
Cómo aplicarlo en tripletex_client.py
Pide esto a Cursor:
Update app/tripletex_client.py to support one safe retry for selected 400/422 validation failures.

Requirements:
- only retry POST and PUT
- only retry once
- use retry_policy.should_retry_validation_error(...)
- use retry_policy.normalize_payload_for_retry(...)
- only retry if normalized payload is different from the original
- log retry_attempted and retry_succeeded/retry_failed
- keep the implementation concise
Patrón recomendado dentro de _request
from app.retry_policy import normalize_payload_for_retry, should_retry_validation_error
Y dentro de _request, en POST/PUT, alrededor de _handle_response:
        try:
            return self._handle_response(response)
        except TripletexValidationError as exc:
            if method not in {"POST", "PUT"} or json_body is None:
                raise

            if not should_retry_validation_error(str(exc), json_body):
                raise

            normalized = normalize_payload_for_retry(path, json_body)
            if normalized == json_body:
                raise

            log_event(
                logger,
                "retry_attempted",
                request_id=request_id,
                method=method,
                path=path,
            )

            retry_start = time.perf_counter()
            retry_response = self.session.request(
                method=method,
                url=url,
                params=params,
                json=normalized,
                timeout=self.timeout,
            )
            retry_elapsed_ms = int((time.perf_counter() - retry_start) * 1000)

            if self.execution_context:
                self.execution_context.api_call_count += 1

            log_event(
                logger,
                "tripletex_api_call",
                request_id=request_id,
                method=method,
                path=path,
                status_code=retry_response.status_code,
                elapsed_ms=retry_elapsed_ms,
            )

            try:
                result = self._handle_response(retry_response)
                log_event(
                    logger,
                    "retry_succeeded",
                    request_id=request_id,
                    method=method,
                    path=path,
                )
                return result
            except Exception:
                log_event(
                    logger,
                    "retry_failed",
                    request_id=request_id,
                    method=method,
                    path=path,
                )
                raise
________________________________________
9. Tests para retry policy
Prompt para Cursor
Create tests/test_retry_policy.py.

Requirements:
- test should_retry_validation_error returns true for likely validation messages
- test normalize_payload_for_retry removes empty fields
- test employee payload normalization maps phone to mobileNumber
- test invoice payload normalization converts numeric strings
tests/test_retry_policy.py
from app.retry_policy import normalize_payload_for_retry, should_retry_validation_error


def test_should_retry_validation_error():
    assert should_retry_validation_error("Validation error: unknown field", {"a": 1}) is True
    assert should_retry_validation_error("Server exploded", {"a": 1}) is False


def test_remove_empty_fields():
    payload = {"name": "Test", "email": "", "phone": None}
    normalized = normalize_payload_for_retry("/employee", payload)
    assert normalized["name"] == "Test"
    assert "email" not in normalized
    assert "phone" not in normalized


def test_employee_phone_normalization():
    payload = {"firstName": "Ola", "lastName": "Nordmann", "phone": "+47 12345678"}
    normalized = normalize_payload_for_retry("/employee", payload)
    assert "phone" not in normalized
    assert normalized["mobileNumber"] == "+47 12345678"


def test_invoice_numeric_normalization():
    payload = {
        "customer": {"id": 1},
        "orderLines": [{"count": "2", "unitPrice": "1500"}],
    }
    normalized = normalize_payload_for_retry("/invoice", payload)
    assert normalized["orderLines"][0]["count"] == 2
    assert normalized["orderLines"][0]["unitPrice"] == 1500.0
________________________________________
10. Recomendaciones prácticas de logging
En Cloud Run, estas son las entradas más útiles:
•	solve_started
•	intent_parsed
•	workflow_selected
•	tripletex_api_call
•	retry_attempted
•	retry_succeeded
•	retry_failed
•	workflow_completed
•	solve_failed
Eso os permitirá ver rápido:
•	qué intent entendió el sistema,
•	cuántas llamadas API hace,
•	dónde falla,
•	si el retry aporta valor o está metiendo ruido.
________________________________________
11. Recomendación práctica sobre retries
Usad retry seguro solo en:
•	create_employee
•	create_customer
•	create_product
•	create_project
•	create_invoice
Pero evitad meter demasiada magia en DELETE o flujos correctivos complejos.
Para esta competición, un retry prudente puede ayudar, pero un sistema “demasiado listo” suele empeorar eficiencia.
________________________________________
12. Orden recomendado de implementación
1.	tests básicos
2.	logging estructurado
3.	execution context
4.	api_call_count
5.	retry policy
6.	tests de retry
7.	revisar logs reales en Cloud Run
8.	ajustar solo donde los logs lo justifiquen
________________________________________
13. Prompt final para Cursor
Now implement the hardening pack on top of the current Tripletex agent.

Tasks:
1. add pytest tests for health, solve, prompt parser, task router, Tripletex client, employee/customer/product workflows, and retry policy
2. add structured logging suitable for Google Cloud Run
3. add ExecutionContext with request_id, elapsed_ms, workflow_name, and api_call_count
4. add one safe retry for selected POST/PUT 400/422 validation failures
5. keep the implementation conservative, simple, and production-style
6. do not redesign the architecture

After implementation, summarize:
- which files were added or changed
- how the retry policy works
- which logs are emitted
- what should be tested manually first
________________________________________
14. Qué probar manualmente después
Hazlo en este orden:
1.	pytest
2.	/health
3.	/solve local con create_employee
4.	/solve local con create_customer
5.	/solve local con create_product
6.	Cloud Run deploy
7.	revisar logs de una llamada real
8.	probar create_project
9.	probar create_invoice
________________________________________
15. Recomendación final
Con este Pack 4 ya pasáis de “demo funcional” a “base seria de competición”. La siguiente mejora útil ya no sería tanto de infraestructura, sino de inteligencia controlada:
•	parser mejor,
•	payloads exactos de Tripletex,
•	y cobertura de más workflows.
En el siguiente paso te preparo un Pack 5 de optimización competitiva, centrado en:
•	reducir llamadas API,
•	mejorar parser multilingüe,
•	y endurecer create_invoice / create_project con payloads más realistas.

Ignacio Tejera
Mars 2026
