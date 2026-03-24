Plan de la NM i AI 2026 para el Ejercicio 2: Tripletex
Pack 5, Pack 6 y Pack 7
En el siguiente paso te preparo un Pack 5 de optimización competitiva, centrado en:
•	reducir llamadas API,
•	mejorar parser multilingüe,
•	y endurecer create_invoice / create_project con payloads más realistas.
Ignacio: preparame un Pack 5 de optimización competitiva, centrado en:
•	reducir llamadas API,
•	mejorar parser multilingüe,
•	y endurecer create_invoice / create_project con payloads más realistas.

Voy a revisar los ficheros de Tripletex para afinar el Pack 5 con foco en eficiencia, multilenguaje y payloads más realistas. Luego te lo dejo en formato directo para Cursor.
Tenkte i 9s
Ignacio: sí. Aquí tienes el Pack 5 de optimización competitiva para Cursor, centrado en lo que más puede mover score en Tripletex:
•	reducir llamadas API
•	mejorar parser multilingüe
•	endurecer create_invoice / create_project con payloads más realistas
La propia documentación apunta justo en esa dirección: el score premia corrección + eficiencia, una cuenta nueva empieza vacía en cada submission, los prompts llegan en 7 idiomas, y para facturas el patrón recomendado suele ser buscar/crear prerequisitos → POST /order → POST /invoice, no solo POST /invoice directo. También recomiendan plan before calling, evitar GETs innecesarios y usar el ID devuelto por los POST en vez de releer lo creado. 
________________________________________
Pack 5 — Competitive Optimization for Tripletex
1. Objetivo de esta iteración
Hasta ahora tenéis una base funcional. En esta iteración, el objetivo ya no es “que funcione”, sino que funcione mejor en competición:
1.	menos llamadas
2.	menos 4xx
3.	mejor extracción de intención en varios idiomas
4.	payloads de proyecto/factura más alineados con Tripletex real
________________________________________
2. Estrategia general
Cambio principal
Pasamos de una arquitectura “workflow simple” a una arquitectura “workflow con plan previo”.
Antes de tocar la API, el sistema debe producir un execution plan como este:
{
  "task_type": "create_invoice",
  "must_find": ["customer", "product"],
  "must_create": ["order", "invoice"],
  "can_skip_verification": True,
  "search_keys": {
    "customer_name": "Nordic Bakery AS",
    "product_name": "Consulting Hour"
  }
}
Esto sigue la recomendación oficial de planificar antes de llamar, minimizar prueba-error y no gastar GETs innecesarios. 
________________________________________
3. Optimización 1: reducir llamadas API
Qué hay que cambiar
Ahora mismo el agente probablemente hace:
•	parser
•	buscar cliente
•	buscar producto
•	crear entidad
•	volver a verificar con GET
Eso da robustez, pero a veces gasta demasiado.
Regla nueva
Regla A
No verificar con GET si el POST ya devuelve el id y no hay campos dudosos.
Regla B
No buscar si el workflow sabe que la cuenta empieza vacía y el prompt pide crear algo nuevo sin ambigüedad.
Esto es importante: en competición cada submission usa una cuenta nueva. Eso significa que para muchas tareas simples no hace falta gastar una búsqueda defensiva inicial. 
Regla C
Para flujos multi-step:
•	buscar solo entidades de referencia que deban existir antes,
•	reutilizar IDs devueltos por POST,
•	no reconsultar lo recién creado.
________________________________________
Nuevo enfoque por tipo de workflow
create_employee
•	si el prompt es claramente “create employee X” y no pide update:
o	hacer POST /employee
o	sin GET previo
o	sin GET posterior salvo fallo o duda
create_customer
•	POST /customer
•	sin búsqueda previa salvo si el prompt sugiere update o deduplicación explícita
create_product
•	POST /product
•	igual que customer
create_project
•	solo buscar customer si el proyecto debe ir ligado a customer existente
•	después POST /project
•	no reconsultar proyecto
create_invoice
•	buscar customer
•	buscar producto(s) solo si vienen por nombre
•	crear order
•	crear invoice con orders: [{"id": order_id}]
•	no reconsultar invoice salvo fallo
Esto encaja mejor con el ejemplo oficial de factura.
________________________________________
Prompt para Cursor — optimización de llamadas
Optimize the current Tripletex agent to reduce API calls.

Requirements:
- add a lightweight planning step before workflow execution
- avoid verification GET calls when the POST response already provides sufficient IDs
- for create-style tasks in fresh accounts, avoid duplicate-check GET calls unless the prompt suggests update/modify semantics
- reuse IDs returned by POST responses
- keep GET calls only for required dependencies such as customer/product lookup before invoice/project creation
- add a per-workflow "api_call_budget" note in logs for debugging
- keep behavior deterministic and conservative
________________________________________
4. Añadir un mini planner
Nuevo archivo recomendado
app/planner.py
Qué debe hacer
Tomar ParsedIntent y devolver:
•	task_type
•	dependencias necesarias
•	estrategia de búsqueda
•	si debe verificar
•	si el flujo puede asumir cuenta vacía
Prompt para Cursor
Create app/planner.py.

Purpose:
Build a lightweight execution plan from ParsedIntent.

Requirements:
- input: ParsedIntent
- output: a simple dict or model with:
  - task_type
  - required_dependencies
  - should_verify
  - assume_fresh_account
  - search_strategy
- logic:
  - create_employee/customer/product in fresh accounts should avoid duplicate-check GETs by default
  - create_project should look up customer only if customer linkage is present
  - create_invoice should look up customer and product references, then create order and invoice
- keep it simple and deterministic
________________________________________
5. Optimización 2: parser multilingüe mejor
La documentación dice que los prompts pueden llegar en:
•	nb
•	en
•	es
•	pt
•	nn
•	de
•	fr
El parser actual seguramente detecta keywords básicas. Eso no basta.
Qué mejorar
A. Separar:
•	detección de idioma
•	detección de acción
•	detección de entidad principal
•	extracción de relaciones
B. Añadir diccionarios por idioma
No hace falta un LLM para todo. Primero, haced un parser híbrido:
•	tabla de verbos por idioma
•	tabla de entidades por idioma
•	regex compartidas para email, teléfono, fechas, importes, cantidades
C. Introducir normalización semántica
Mapear todo a un vocabulario interno:
•	create_employee
•	create_customer
•	create_product
•	create_project
•	create_invoice
•	update_customer
•	delete_travel_expense
________________________________________
Diccionario mínimo recomendado
ACTION_KEYWORDS = {
    "create": ["create", "crear", "opprett", "lag", "criar", "erstellen", "créer"],
    "update": ["update", "actualizar", "oppdater", "endre", "atualizar", "aktualisieren", "mettre à jour"],
    "delete": ["delete", "eliminar", "slett", "apagar", "löschen", "supprimer"],
    "register": ["register", "registrar", "registrer", "registrar", "registrieren", "enregistrer"],
}

ENTITY_KEYWORDS = {
    "employee": ["employee", "empleado", "ansatt", "funcionário", "mitarbeiter", "employé"],
    "customer": ["customer", "cliente", "kunde", "client"],
    "product": ["product", "producto", "produkt", "produit"],
    "project": ["project", "proyecto", "prosjekt", "projeto", "projekt", "projet"],
    "invoice": ["invoice", "factura", "faktura", "rechnung", "facture"],
}
________________________________________
Prompt para Cursor — parser multilingüe
Upgrade app/prompt_parser.py into a stronger multilingual rule-based parser.

Requirements:
- separate:
  1. language detection
  2. action detection
  3. primary entity detection
  4. field extraction
- support nb, en, es, pt, nn, de, fr
- use internal normalized actions:
  create, update, delete, register, reverse
- use internal normalized task types:
  create_employee, create_customer, create_product, create_project, create_invoice
- extract:
  - names
  - emails
  - phone numbers
  - dates
  - quantities
  - amounts / unit prices
  - customer_name
  - product_name
  - project_name
- for invoice prompts, support one or more simple line items
- keep the parser deterministic and maintainable
- do not require an LLM for version 1
________________________________________
Estructura recomendada del parser
Dividid prompt_parser.py así:
•	detect_language(text)
•	detect_action(text, lang)
•	detect_entity(text, lang)
•	extract_common_fields(text)
•	extract_project_fields(text, lang)
•	extract_invoice_fields(text, lang)
•	parse_prompt(text)
________________________________________
Ejemplos que debe cubrir
Español
Crea un proyecto llamado Migración ERP para el cliente Nordic Bakery AS
Noruego
Opprett en faktura for kunden Nordic Bakery AS med 2 timer Consulting Hour til 1500 kr
Alemán
Erstellen Sie ein Produkt namens Consulting Hour
Francés
Créer un client nommé Nordic Bakery AS avec e-mail post@nordicbakery.no
________________________________________
6. Optimización 3: endurecer create_project
La documentación lista /project como endpoint estándar, y los proyectos están ligados a clientes en los ejemplos de tareas.
Recomendación de flujo realista
Si el prompt solo dice “create project”
•	POST /project con name
Si dice “for customer X”
•	GET /customer?name=...
•	POST /project con customer link
Payload objetivo
payload = {
    "name": project_name,
    "customer": {"id": customer_id}
}
Mejoras recomendadas
•	permitir description si aparece
•	permitir startDate y endDate si aparecen
•	no fallar si campos opcionales no están
•	no verificar por GET salvo que el POST devuelva algo incompleto
________________________________________
Prompt para Cursor — endurecer create_project.py
Harden app/workflows/create_project.py.

Requirements:
- support required field: project name
- support optional fields:
  - customer_name
  - description
  - start_date
  - end_date
- use planner guidance to decide whether customer lookup is required
- if customer_name is present, look up customer and link it in the project payload
- create project with a realistic payload
- do not verify with GET if the POST response already contains the new project ID
- only raise not found if customer linkage is required and customer cannot be resolved
- keep the workflow deterministic and efficient
________________________________________
Versión más realista de create_project.py
from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateProjectWorkflow(BaseWorkflow):
    name = "create_project"

    def validate_intent(self, intent: ParsedIntent) -> None:
        project = intent.entities.get("project", {})
        if not str(project.get("name", "")).strip():
            raise TripletexValidationError("Project name is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        plan = context.get("plan", {})
        project = intent.entities.get("project", {})

        project_name = str(project.get("name", "")).strip()
        customer_name = intent.fields.get("customer_name")
        description = intent.fields.get("description")
        start_date = intent.fields.get("start_date")
        end_date = intent.fields.get("end_date")

        payload = {"name": project_name}

        if description:
            payload["description"] = description
        if start_date:
            payload["startDate"] = start_date
        if end_date:
            payload["endDate"] = end_date

        if plan.get("search_strategy", {}).get("lookup_customer") and customer_name:
            customer = client.find_customer_by_name(customer_name)
            if not customer:
                raise TripletexNotFoundError(f"Customer not found for project: {customer_name}")
            payload["customer"] = {"id": customer["id"]}

        created = client.post("/project", json_body=payload)

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={"project_id": created.get("id")},
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification
________________________________________
7. Optimización 4: endurecer create_invoice
Aquí está la mejora más importante.
La documentación y ejemplos muestran este patrón:
•	buscar customer
•	crear order
•	crear invoice con orders: [{"id": order_id}]
Eso es mejor que asumir que POST /invoice acepta directamente todas las líneas.
Flujo recomendado
Paso 1
Resolver customer:
•	GET /customer?name=...
Paso 2
Resolver productos si hay nombres de producto
•	GET /product?name=...
Paso 3
Crear order
•	con customer
•	con orderLines
Paso 4
Crear invoice
•	con invoiceDate
•	con invoiceDueDate
•	con customer
•	con orders: [{"id": order_id}]
Paso 5
No reconsultar invoice salvo error
________________________________________
Payloads objetivo
POST /order
{
  "customer": {"id": customer_id},
  "orderLines": [
    {
      "product": {"id": product_id},
      "count": 2,
      "unitPrice": 1500.0,
      "description": "Consulting Hour"
    }
  ]
}
POST /invoice
{
  "invoiceDate": "2026-03-20",
  "invoiceDueDate": "2026-03-20",
  "customer": {"id": customer_id},
  "orders": [{"id": order_id}]
}
________________________________________
Prompt para Cursor — endurecer create_invoice.py
Harden app/workflows/create_invoice.py to use a more realistic Tripletex flow.

Requirements:
- require customer_name
- require at least one invoice line
- resolve customer first
- resolve product IDs when product_name is provided
- create an order first using /order
- create the invoice second using /invoice and orders:[{"id": order_id}]
- support optional invoice_date and due_date
- use invoiceDueDate instead of dueDate in the final invoice payload
- support line fields:
  - product_name
  - description
  - quantity
  - unit_price
- convert quantity and unit_price to numeric types safely
- avoid unnecessary GET verification after successful POSTs
- keep the workflow deterministic and efficient
________________________________________
Versión más realista de create_invoice.py
from datetime import date

from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient, TripletexNotFoundError, TripletexValidationError
from app.workflows.base import BaseWorkflow


class CreateInvoiceWorkflow(BaseWorkflow):
    name = "create_invoice"

    def validate_intent(self, intent: ParsedIntent) -> None:
        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])
        if not str(customer_name or "").strip():
            raise TripletexValidationError("Invoice customer_name is required")
        if not isinstance(lines, list) or not lines:
            raise TripletexValidationError("At least one invoice line is required")

    def execute(self, intent: ParsedIntent, client: TripletexClient, context: dict) -> ExecutionResult:
        self.validate_intent(intent)

        invoice = intent.entities.get("invoice", {})
        customer_name = invoice.get("customer_name") or intent.fields.get("customer_name")
        lines = invoice.get("lines", [])
        invoice_date = invoice.get("invoice_date") or intent.fields.get("invoice_date") or str(date.today())
        due_date = invoice.get("due_date") or intent.fields.get("due_date") or invoice_date

        customer = client.find_customer_by_name(customer_name)
        if not customer:
            raise TripletexNotFoundError(f"Customer not found for invoice: {customer_name}")
        customer_id = customer["id"]

        order_lines = [self._build_order_line(line, client) for line in lines]

        order_payload = {
            "customer": {"id": customer_id},
            "orderLines": order_lines,
        }
        created_order = client.post("/order", json_body=order_payload)
        order_id = created_order.get("id")
        if not order_id:
            raise TripletexValidationError("Order creation did not return an id")

        invoice_payload = {
            "invoiceDate": invoice_date,
            "invoiceDueDate": due_date,
            "customer": {"id": customer_id},
            "orders": [{"id": order_id}],
        }
        created_invoice = client.post("/invoice", json_body=invoice_payload)

        return ExecutionResult(
            success=True,
            workflow_name=self.name,
            created_ids={
                "order_id": order_id,
                "invoice_id": created_invoice.get("id"),
            },
            notes=[],
            verification={"skipped_get_verify": True},
        )

    def verify(self, intent: ParsedIntent, client: TripletexClient, execution_result: ExecutionResult) -> dict:
        return execution_result.verification

    def _build_order_line(self, raw_line: dict, client: TripletexClient) -> dict:
        if not isinstance(raw_line, dict):
            raise TripletexValidationError("Invoice line must be an object")

        quantity = raw_line.get("quantity", 1)
        unit_price = raw_line.get("unit_price")
        product_name = raw_line.get("product_name")
        description = raw_line.get("description")

        try:
            quantity = int(quantity)
        except (TypeError, ValueError):
            raise TripletexValidationError(f"Invalid quantity: {quantity}")

        if unit_price is not None:
            try:
                unit_price = float(unit_price)
            except (TypeError, ValueError):
                raise TripletexValidationError(f"Invalid unit_price: {unit_price}")

        line = {"count": quantity}

        if unit_price is not None:
            line["unitPrice"] = unit_price

        if product_name:
            product = client.find_product_by_name(product_name)
            if not product:
                raise TripletexNotFoundError(f"Product not found: {product_name}")
            line["product"] = {"id": product["id"]}

        if description:
            line["description"] = description
        elif product_name:
            line["description"] = product_name

        return line
________________________________________
8. Extensiones necesarias en tripletex_client.py
Añadid helpers más específicos.
Prompt para Cursor
Extend app/tripletex_client.py with more realistic Tripletex helper methods.

Add:
- create_order(customer_id, order_lines)
- create_invoice_from_order(customer_id, order_id, invoice_date=None, due_date=None)
- maybe_find_customer_exact(name)
- maybe_find_product_exact(name)

Requirements:
- keep helper methods thin wrappers over POST/GET
- prefer exact-name filtering when possible
- do not redesign the client
Métodos recomendados
    def maybe_find_customer_exact(self, name: str) -> dict | None:
        matches = self.list_values(
            "/customer",
            params={"name": name, "fields": "id,name,email", "count": 10},
        )
        target = name.strip().lower()
        for item in matches:
            if str(item.get("name", "")).strip().lower() == target:
                return item
        return matches[0] if matches else None

    def maybe_find_product_exact(self, name: str) -> dict | None:
        matches = self.list_values(
            "/product",
            params={"name": name, "fields": "id,name,productNumber", "count": 10},
        )
        target = name.strip().lower()
        for item in matches:
            if str(item.get("name", "")).strip().lower() == target:
                return item
        return matches[0] if matches else None

    def create_order(self, customer_id: int, order_lines: list[dict]) -> dict:
        payload = {
            "customer": {"id": customer_id},
            "orderLines": order_lines,
        }
        return self.post("/order", json_body=payload)

    def create_invoice_from_order(
        self,
        customer_id: int,
        order_id: int,
        invoice_date: str | None = None,
        due_date: str | None = None,
    ) -> dict:
        payload = {
            "customer": {"id": customer_id},
            "orders": [{"id": order_id}],
        }
        if invoice_date:
            payload["invoiceDate"] = invoice_date
        if due_date:
            payload["invoiceDueDate"] = due_date
        return self.post("/invoice", json_body=payload)
________________________________________
9. Mejoras concretas del parser para invoice y project
create_project
Extraed:
•	project_name
•	customer_name
•	description
•	start_date
•	end_date
create_invoice
Extraed:
•	customer_name
•	invoice_date
•	due_date
•	lines[]
o	product_name
o	description
o	quantity
o	unit_price
Recomendación práctica
Para invoices, limitad versión 1 a:
•	1–3 líneas
•	quantity y unit_price explícitos
•	un único customer por prompt
________________________________________
Prompt para Cursor — patrones multilingües de invoice/project
Extend the parser with multilingual invoice/project extraction patterns.

Requirements:
- for projects, support patterns like:
  - "create a project named X for customer Y"
  - "crea un proyecto llamado X para el cliente Y"
  - "opprett et prosjekt kalt X for kunden Y"
  - equivalent simple forms in pt, nn, de, fr
- for invoices, support patterns like:
  - "create an invoice for customer Y with one line for X, quantity 2, unit price 1500"
  - "crea una factura para el cliente Y con una línea de X, cantidad 2, precio unitario 1500"
  - "opprett en faktura for kunden Y med 2 av X til 1500"
- extract dates in simple ISO or obvious date forms when present
- normalize all outputs into the current ParsedIntent schema
________________________________________
10. Tests nuevos para esta iteración
Añadid tests justo en las partes que más cambian.
Prompt para Cursor
Add competitive optimization tests.

Create tests for:
- planner behavior for create_employee/create_project/create_invoice
- multilingual parser for English, Spanish, Norwegian, German, French
- create_project workflow uses customer lookup only when needed
- create_invoice workflow calls:
  1. customer lookup
  2. product lookup if needed
  3. POST /order
  4. POST /invoice
- verify no extra GET verification is performed after successful POSTs
Casos mínimos a cubrir
Planner
•	create_employee -> assume_fresh_account=True, should_verify=False
•	create_project con customer -> lookup_customer=True
•	create_invoice -> lookup_customer=True, lookup_product=True, should_verify=False
Parser
•	ES project
•	NB invoice
•	EN invoice
•	DE product
•	FR customer
Workflow invoice
Mockear:
•	customer lookup
•	product lookup
•	POST /order
•	POST /invoice
y comprobar que no haya más llamadas.
________________________________________
11. Logging competitivo
Añadid 2 eventos nuevos:
•	execution_plan_created
•	api_budget_summary
Ejemplo
log_event(
    logger,
    "execution_plan_created",
    request_id=ctx.request_id,
    task_type=plan["task_type"],
    required_dependencies=plan["required_dependencies"],
    should_verify=plan["should_verify"],
)
log_event(
    logger,
    "api_budget_summary",
    request_id=ctx.request_id,
    workflow_name=ctx.workflow_name,
    api_call_count=ctx.api_call_count,
    elapsed_ms=ctx.elapsed_ms(),
)
Esto os permite ver rápido si un workflow se está “pasando” de llamadas.
________________________________________
12. Orden recomendado de implementación
1.	planner.py
2.	integrar planner en orchestrator.py
3.	mejorar prompt_parser.py
4.	endurecer create_project.py
5.	endurecer create_invoice.py
6.	extender tripletex_client.py
7.	tests nuevos
8.	revisar logs reales
9.	ajustar payloads exactos con sandbox
________________________________________
13. Prompt final para Cursor
Implement Pack 5 competitive optimization on top of the current Tripletex agent.

Tasks:
1. add a lightweight planner module
2. reduce unnecessary API calls by using planner guidance
3. improve the multilingual parser for nb, en, es, pt, nn, de, fr
4. harden create_project with optional customer/date/description support
5. harden create_invoice to use the realistic Tripletex flow:
   customer lookup -> product lookup if needed -> POST /order -> POST /invoice
6. extend tripletex_client with order/invoice helper methods
7. add tests for planner, multilingual parsing, project workflow, and invoice workflow
8. add logging for execution_plan_created and api_budget_summary

Constraints:
- keep the architecture stable
- stay deterministic
- optimize for fewer API calls and fewer 4xx errors
- avoid unnecessary GET verification after successful POSTs

After implementation, summarize:
- files added/changed
- estimated API call reduction by workflow
- invoice/project payload assumptions that should be validated in the sandbox
________________________________________
14. Qué validar manualmente en el sandbox
Esta parte sí merece validación rápida manual, porque aquí está la mayor incertidumbre real:
project
•	nombre exacto del campo customer link
•	si acepta description
•	si acepta startDate / endDate
order
•	estructura exacta de orderLines
•	nombre exacto de count
•	nombre exacto de unitPrice
•	si description y product pueden convivir
invoice
•	invoiceDate
•	invoiceDueDate
•	orders: [{"id": ...}]
Los ejemplos oficiales sí apuntan a invoiceDate, invoiceDueDate, customer, y orders, así que esa es la mejor hipótesis inicial.
________________________________________
15. Mi recomendación práctica final
Si queréis mover score rápido, la mejora más rentable de este Pack 5 es create_invoice. Ahí es donde más fácilmente podéis ganar:
•	corrección estructural
•	menos 4xx
•	menos llamadas inútiles
Después, el segundo mayor retorno os vendrá del planner + parser multilingüe.
Cuando quieras, te preparo un Pack 6 de “submission tactics”, centrado en:
•	qué probar con las 2–3 submissions diarias,
•	cómo priorizar workflows por retorno,
•	y cómo leer los logs para decidir el siguiente cambio.
Ignacio: si gracias,  preparame un Pack 6 de “submission tactics”, centrado en:
•	qué probar con las 2–3 submissions diarias,
•	cómo priorizar workflows por retorno,
•	y cómo leer los logs para decidir el siguiente cambio.
Voy a apoyarme en la documentación que subiste para que el Pack 6 esté alineado con límites reales de submissions, scoring y señales útiles de logs.
Tenkte i 10s
Ignacio: aquí va el Pack 6 de submission tactics para Tripletex, pensado para exprimir bien las 2–3 submissions al día, priorizar por retorno y usar los logs para decidir el siguiente cambio.
La base estratégica sale clara de la documentación: cada submission usa una cuenta nueva y vacía, el score mezcla corrección + eficiencia, los 4xx reducen eficiencia, y todas las llamadas por proxy quedan registradas, así que los logs son la mejor señal para iterar. Además, Tripletex tiene 30 tipos de tareas, 56 variantes por tarea y el timeout es de 300 s, así que no conviene “tocar de todo” entre submissions; conviene hacer cambios pequeños y medibles. 
________________________________________
Pack 6 — Submission Tactics
1. Objetivo real de esta fase
No buscar “más features” por defecto.
Buscar esto:
•	subir la probabilidad de acierto en los workflows más frecuentes y valiosos,
•	bajar errores evitables,
•	y aprender algo claro de cada submission.
Una submission que no os enseña nada útil casi siempre está mal planteada.
________________________________________
2. Regla principal para las 2–3 submissions diarias
Una submission = una hipótesis clara
Cada submission debe responder a una pregunta concreta, por ejemplo:
•	“¿El nuevo parser multilingüe mejora prompts en alemán/francés sin aumentar 4xx?”
•	“¿Cambiar invoice a POST /order -> POST /invoice reduce fallos 422?”
•	“¿Quitar GETs de verificación mejora eficiencia sin bajar corrección?”
No mezclar 5 cambios grandes en una misma subida.
Si mezcláis parser + retry + invoice + project + archivos, luego no sabréis qué causó la mejora o la caída.
________________________________________
3. Cómo usar las 2–3 submissions del día
Opción recomendada: estrategia 1–1–1
Submission 1 — Safe baseline
Subid la versión más estable que tengáis en ese momento.
Objetivo:
•	asegurar una puntuación base,
•	confirmar que Cloud Run, auth, /solve y workflows nucleares siguen sanos.
Debe ser la versión con:
•	menos riesgo,
•	menos experimentación,
•	mejor trazabilidad.
Submission 2 — Highest-impact improvement
Aquí probáis un solo cambio importante.
Ejemplos buenos:
•	parser multilingüe mejorado,
•	invoice con flujo customer -> order -> invoice,
•	eliminación de GETs de verificación.
Submission 3 — Targeted fix
Solo si lo aprendido en logs/score de la submission 2 es claro.
Ejemplos:
•	corregir payload de invoiceDueDate,
•	corregir una extracción rota de customer name,
•	volver a activar una búsqueda necesaria que quitasteis demasiado agresivamente.
________________________________________
Opción conservadora: estrategia 1–2
Si vais justos de tiempo o está inestable:
Submission 1
baseline sólida.
Submission 2
mejora puntual basada en logs.
Guardad la tercera sin usar hasta tener evidencia real.
________________________________________
4. Qué probar primero con pocas submissions
La documentación deja bastante claro qué da retorno alto:
•	prompts en 7 idiomas,
•	field-by-field correctness,
•	bonus por eficiencia,
•	tareas multi-step como invoice / payment / project / corrections,
•	cuenta vacía en cada submission. 
Orden recomendado de experimentación
Prioridad A — invoice
Es el workflow con más palancas:
•	parser,
•	búsqueda de customer/product,
•	POST /order,
•	POST /invoice,
•	payload exacto,
•	eficiencia.
Si mejoráis create_invoice, el impacto esperado es alto.
Prioridad B — parser multilingüe
Porque afecta transversalmente a muchas tareas.
Un parser mejor puede mejorar varias categorías a la vez sin tocar todos los workflows.
Prioridad C — project
Es más simple que invoice, pero suele involucrar relación con customer y puede dar fallos de linking.
Prioridad D — customer / product / employee
Son importantes, pero normalmente tienen menos complejidad y menos superficie de fallo que invoice.
Prioridad E — travel expense / reverse / departments
Solo después de tener sólido el núcleo, salvo que en logs veáis claramente que os está penalizando ahí.
________________________________________
5. Cómo priorizar workflows por retorno
Usad esta fórmula sencilla:
Retorno esperado = impacto × frecuencia × controlabilidad
Impacto
¿Cuánto puede mover score si lo arregláis?
•	Alto: invoice, payment, corrections
•	Medio: project, customer/product linkage
•	Bajo/medio: create single entity simple
Frecuencia
¿Cuántas tareas/variantes probablemente tocan ese patrón?
La doc menciona familias recurrentes:
•	employees,
•	customers/products,
•	invoicing,
•	travel expenses,
•	projects,
•	corrections,
•	departments. 
Controlabilidad
¿Qué tan fácil es mejorarlo rápido sin romper otras cosas?
•	Alta: employee/customer/product
•	Media: project
•	Media-baja: invoice
•	Baja: corrections con reglas contables más delicadas
________________________________________
Mi ranking práctico
Tier 1 — tocar ya
1.	create_invoice
2.	parser multilingüe
3.	create_project
Tier 2 — consolidar
4.	create_customer
5.	create_product
6.	create_employee
Tier 3 — después
7.	payments
8.	travel expense delete/reverse
9.	departments / enable modules
________________________________________
6. Qué cambiar entre submissions y qué no
Cambios buenos entre submissions
•	un payload,
•	una heurística del parser,
•	una regla del planner,
•	un endpoint concreto,
•	una verificación innecesaria menos,
•	una normalización segura más.
Cambios malos entre submissions
•	refactor grande,
•	reescritura de arquitectura,
•	cambiar parser + planner + retries + deploy a la vez,
•	cambiar logging y lógica simultáneamente,
•	tocar 6 workflows sin tests.
________________________________________
7. Cómo leer los logs para decidir el siguiente cambio
La documentación dice que las llamadas por proxy quedan registradas y que los 4xx afectan eficiencia. También recomiendan leer bien el mensaje de error y corregir en un solo retry. 
Lo que debes mirar primero en logs
1. workflow_selected
Pregunta:
•	¿Estamos clasificando bien el prompt?
Señal de problema:
•	prompt de invoice entrando en customer,
•	project entrando como product,
•	unsupported demasiado frecuente.
2. intent_parsed
Pregunta:
•	¿faltan campos clave?
Señal de problema:
•	customer_name=None,
•	líneas vacías en invoice,
•	quantities mal parseadas,
•	idioma detectado raro.
3. tripletex_api_call
Pregunta:
•	¿El orden de llamadas tiene sentido?
Patrones correctos:
•	employee simple: POST /employee
•	project linked: GET /customer → POST /project
•	invoice: GET /customer → GET /product (si hace falta) → POST /order → POST /invoice
Patrones malos:
•	demasiados GET seguidos,
•	POST duplicados,
•	verificación innecesaria tras POST exitoso,
•	búsquedas antes de create en cuenta vacía sin motivo.
4. retry_attempted
Pregunta:
•	¿el retry está arreglando errores o solo metiendo ruido?
Bueno:
•	1 retry, luego éxito.
Malo:
•	retries frecuentes,
•	retry sobre payload idéntico,
•	retry seguido de otro 422 similar.
5. api_budget_summary
Pregunta:
•	¿cuántas llamadas se gastan por workflow?
Regla práctica:
•	single entity: ideal 1 llamada
•	project con customer: ideal 2 llamadas
•	invoice con product: ideal 3–4 llamadas
Si veis 6–9 llamadas en esos casos, hay oportunidad clara.
________________________________________
8. Árbol de decisión rápido a partir de logs
Caso A — muchos unsupported
Siguiente cambio:
•	mejorar parser / router, no payloads.
Caso B — muchos 404
Siguiente cambio:
•	revisar path o flujo de endpoints.
Caso C — muchos 422
Siguiente cambio:
•	revisar payload exacto, tipos y campos obligatorios.
Caso D — pocos errores pero score no sube
Siguiente cambio:
•	recortar GETs,
•	quitar verify innecesario,
•	usar IDs de POST,
•	revisar eficiencia.
Caso E — fallos solo en idiomas no ingleses
Siguiente cambio:
•	parser multilingüe, no workflows.
Caso F — invoice falla más que todo lo demás
Siguiente cambio:
•	dedicar la siguiente submission entera a invoice.
________________________________________
9. Plantilla de análisis después de cada submission
Usad este formato, siempre igual:
Submission N:
- Goal:
- Version tag:
- Main hypothesis:
- Score result:
- What improved:
- What regressed:
- Top 3 log patterns:
- Most likely root cause:
- Next single change:
- Keep / revert:
Ejemplo:
Submission 2:
- Goal: test realistic invoice flow
- Version tag: tripletex-pack5-invoice-order
- Main hypothesis: POST /order -> POST /invoice reduces 422
- Score result: +0.18
- What improved: fewer invoice validation failures
- What regressed: more unsupported project prompts
- Top 3 log patterns:
  1. workflow_selected=create_invoice correct
  2. tripletex_api_call GET /customer -> POST /order -> POST /invoice
  3. unsupported on German/French prompts
- Most likely root cause: parser multilingual weak
- Next single change: improve parser for de/fr project+invoice
- Keep / revert: keep invoice flow
________________________________________
10. Táctica de priorización para un día completo
Si tenéis 3 submissions
Submission 1
Baseline estable.
Submission 2
Cambio con mayor retorno probable:
•	normalmente invoice o parser.
Submission 3
Micro-fix basado en logs de la 2:
•	payload,
•	regex,
•	endpoint,
•	verify removal.
________________________________________
Si solo queréis jugar seguro
Día 1
•	baseline
•	invoice hardening
Día 2
•	parser multilingüe
•	project hardening
Día 3
•	efficiency trimming
•	corrections / payments solo si ya está estable
________________________________________
11. Qué NO hacer con pocas submissions
No gastéis una submission en:
•	“a ver si mejora”
•	cambios visuales de logging sin impacto funcional
•	refactors que no cambian score
•	añadir workflows no testeados
•	cambiar deploy/config y lógica a la vez
Y no persigáis todos los errores a la vez.
Perseguid el error que más aparece o el workflow que más peso os puede dar.
________________________________________
12. Táctica específica por workflow
create_employee
Objetivo:
•	1 POST limpio
•	cero verify GET
•	cero duplicate checks salvo evidencia
Si falla:
•	casi siempre parser o payload.
create_customer / create_product
Objetivo:
•	1 POST limpio
•	payload simple
•	no búsquedas previas.
create_project
Objetivo:
•	1 POST si no hay customer link
•	2 llamadas si hay customer link.
Si veis más:
•	estáis sobrebuscando.
create_invoice
Objetivo:
•	3–4 llamadas bien ordenadas.
•	nada más.
Si veis:
•	GET customer,
•	GET product,
•	POST order,
•	POST invoice,
•	GET verify invoice,
•	GET verify order
… seguramente estáis gastando demasiado.
________________________________________
13. Qué métricas mirar en vuestros logs
Haced una mini tabla por submission:
- total requests
- unsupported rate
- avg api_call_count
- 4xx count
- 404 count
- 422 count
- avg elapsed_ms
- top failing workflow
- top failing language
Con eso decidiréis mucho mejor que mirando solo el score total.
________________________________________
14. Prompt para Cursor — añadir resumen táctico en logs
Add a lightweight submission-debug summary to the Tripletex agent logs.

Requirements:
- after each /solve execution, log:
  - request_id
  - workflow_name
  - detected_language
  - api_call_count
  - 4xx_error_count
  - elapsed_ms
  - retry_used
  - result_success
- keep it concise and structured
- do not log secrets
- make it easy to aggregate later from Cloud Run logs
________________________________________
15. Prompt para Cursor — instrumentation por language/workflow
Improve instrumentation for competitive iteration.

Requirements:
- include detected language in intent_parsed logs
- include task_type and workflow_name in summary logs
- include whether verification was skipped
- include whether planner assumed a fresh account
- include whether invoice used order->invoice flow
- keep the code changes minimal
________________________________________
16. Mi recomendación práctica para vuestras próximas submissions
Yo haría esto:
Próxima submission
La mejor baseline actual + Pack 5 invoice flow.
Siguiente
Parser multilingüe mejorado para invoice y project.
Tercera
Recorte de GETs y verify innecesario en workflows simples.
Ese orden maximiza aprendizaje y retorno:
1.	arreglas lo más caro,
2.	aumentas cobertura de prompts,
3.	mejoras eficiencia.
________________________________________
17. Resumen ejecutivo
La mejor táctica en Tripletex no es “hacer más”.
Es esta:
•	una hypothesis por submission,
•	priorizar invoice > parser > project,
•	leer logs por workflow, idioma y número de llamadas,
•	y usar cada submission para confirmar una decisión concreta.
Si quieres, te preparo ahora un Pack 7 ultra práctico con una plantilla de dashboard de logs + checklist pre-submission + checklist post-submission para que lo uséis durante el campeonato.

Ignacio: Si gracias, preparame  ahora un Pack 7 ultra práctico con una plantilla de dashboard de logs + checklist pre-submission + checklist post-submission para que lo usemos  durante el campeonato.
...
Ignacio: sí. Aquí tienes el Pack 7 ultra práctico, pensado para usarlo cada día durante el campeonato en el ejercicio de Tripletex.
Está diseñado para tres cosas:
•	tener una vista rápida de lo que está pasando,
•	decidir qué subir en la siguiente submission,
•	y evitar perder submissions en cambios poco informativos.
La lógica está alineada con el formato real del reto: cada submission corre sobre una cuenta nueva, el score depende de corrección campo a campo + eficiencia, hay 30 tipos de tareas con 56 variantes cada una, y las llamadas al proxy os dejan la mejor pista posible para iterar mediante logs. 
________________________________________
Pack 7 — Championship Ops Kit for Tripletex
1. Cómo usar este pack
Úsalo como ritual fijo:
1.	Antes de subir → checklist pre-submission
2.	Después de subir → checklist post-submission
3.	Durante el análisis → dashboard de logs
4.	Antes de tocar código otra vez → decidir una sola hipótesis
La regla más importante de todas:
Una submission debe enseñaros una sola cosa importante
No “mejorar muchas cosas”.
Aprender una cosa clara.
________________________________________
2. Dashboard de logs — plantilla ultra práctica
Esto lo podéis llevar en:
•	Notion
•	Google Sheets
•	Airtable
•	Markdown en el repo
•	o una mini página interna
Vista 1 — Submission Overview
Usad esta tabla por submission:
Submission ID
Date / Time
Version Tag
Main Hypothesis
Score
Status (better / same / worse)
Keep or Revert
Next Single Change
Ejemplo
Submission ID: S05
Date / Time: 2026-03-20 14:10
Version Tag: tripletex-pack5-invoice-order
Main Hypothesis: order->invoice flow reduces 422 on invoice tasks
Score: 0.61
Status: better
Keep or Revert: keep
Next Single Change: improve parser for German/French invoice prompts
________________________________________
Vista 2 — Operational Metrics Dashboard
Esta es la tabla más útil del campeonato.
Metric
Value
Target
Interpretation
Action
Rellénala así:
Total solve requests
Unsupported rate
Success rate
Average api_call_count
Average elapsed_ms
4xx count
404 count
422 count
Retry used %
Top failing workflow
Top failing language
Top failing endpoint
Verification skipped %
Fresh-account assumption used %
Interpretación recomendada
unsupported rate
•	bajo: bien
•	alto: parser/router es el problema
average api_call_count
•	sube sin subir score: estáis gastando eficiencia
•	baja y score sube: muy buena señal
422 count
•	problema típico de payload / tipos / campos obligatorios
404 count
•	path incorrecto, endpoint incorrecto o flujo equivocado
top failing language
•	parser multilingüe insuficiente
verification skipped %
•	si sube demasiado y cae score, habéis quitado verificación donde sí hacía falta
•	si sube y mejora score, vais bien
________________________________________
Vista 3 — Workflow Heatmap
Usad esta plantilla:
Workflow              Requests   Success %   Avg Calls   4xx   Avg ms   Confidence   Priority
create_employee
create_customer
create_product
create_project
create_invoice
delete_travel_expense
register_payment
correction/reverse
unsupported
Cómo leerla
Si un workflow tiene:
•	muchos requests + bajo success % → prioridad alta
•	pocos requests + muy complejo → no lo toquéis primero
•	bajo success % + alto avg calls → gran candidato para optimización
•	alto 422 → probablemente payload
•	alto unsupported → probablemente parser
________________________________________
Vista 4 — Language Dashboard
Como el reto acepta prompts en varios idiomas, esta tabla es clave. 
Language   Requests   Success %   Unsupported %   Top Failed Task   Notes
en
es
nb
nn
pt
de
fr
unknown
Señales importantes
•	si de/fr van peor que en/es → el siguiente cambio es parser, no workflow
•	si nb/nn fallan en invoice/project → probablemente os falta vocabulario específico
•	si unknown es alto → language detection floja
________________________________________
Vista 5 — Error Taxonomy Dashboard
Error Type                     Count   Top Workflow        Most Likely Cause
Unsupported task              ...
TripletexValidationError 400   ...
TripletexValidationError 422   ...
TripletexNotFoundError         ...
TripletexApiError 404          ...
Timeout / near-timeout         ...
Retry failed                   ...
Unexpected exception           ...
Lectura rápida
•	Unsupported task → parser/router
•	422 → payload
•	NotFound → dependencia no resuelta
•	404 → endpoint/path/flow
•	Retry failed → retry mal planteado o payload base incorrecto
•	Timeout → demasiadas llamadas o flujo demasiado largo
________________________________________
3. Qué logs debéis recoger sí o sí
Si no lo tenéis todavía, vuestro summary por request debería incluir como mínimo:
request_id
submission_tag
workflow_name
task_type
detected_language
result_success
api_call_count
elapsed_ms
4xx_error_count
retry_used
verification_skipped
assume_fresh_account
invoice_order_flow_used
Esto os permite analizar por:
•	workflow,
•	idioma,
•	eficiencia,
•	y tipo de decisión del planner.
La documentación encaja con esta disciplina porque la competición penaliza la ineficiencia y recomienda evitar llamadas innecesarias y 4xx evitables. 
________________________________________
4. Checklist pre-submission
Usadla siempre. Siempre.
A. Objetivo de la submission
[ ] La submission tiene una sola hipótesis principal
[ ] La hipótesis está escrita en una frase
[ ] Sabemos qué métrica o señal de logs debería mejorar
[ ] Sabemos qué empeoramiento aceptaríamos y cuál no
Ejemplo de hipótesis buena
“Cambiar invoice a order->invoice reducirá 422 y mantendrá o mejorará score.”
Ejemplo de hipótesis mala
“Hemos mejorado varias cosas y a ver qué pasa.”
________________________________________
B. Riesgo de cambios
[ ] Solo se toca 1 área principal (parser / workflow / planner / retry / payload)
[ ] No hemos mezclado refactor grande + cambio funcional
[ ] Los workflows simples no se han roto por tocar invoice/project
[ ] El deploy no ha cambiado innecesariamente
[ ] Los logs siguen emitiendo los mismos campos clave
________________________________________
C. Salud del código
[ ] pytest pasa
[ ] /health responde bien en local
[ ] /solve responde bien en local
[ ] create_employee pasa smoke test
[ ] create_customer pasa smoke test
[ ] create_product pasa smoke test
[ ] create_project pasa smoke test si fue tocado
[ ] create_invoice pasa smoke test si fue tocado
________________________________________
D. Validación funcional
[ ] El parser reconoce correctamente el nuevo patrón tocado
[ ] El router selecciona el workflow correcto
[ ] El planner no añade búsquedas innecesarias
[ ] El retry sigue siendo solo de un intento
[ ] No se loguean secretos
________________________________________
E. Eficiencia
[ ] Hemos contado las llamadas esperadas por workflow tocado
[ ] El flujo simple sigue en 1 POST cuando aplica
[ ] project con customer debería usar ~2 llamadas
[ ] invoice debería usar ~3-4 llamadas
[ ] No hay GET de verificación innecesario tras POST exitoso
________________________________________
F. Preparación táctica
[ ] El version tag está definido
[ ] Hemos anotado qué esperamos aprender de esta submission
[ ] Hemos decidido de antemano si el cambio se mantiene o revierte según resultado
[ ] La siguiente submission potencial ya tiene dirección si esta mejora
________________________________________
5. Checklist post-submission
Rellenadla inmediatamente después de ver score y logs.
A. Resultado bruto
[ ] Hemos anotado score
[ ] Hemos anotado fecha/hora
[ ] Hemos anotado version tag
[ ] Hemos marcado better / same / worse
________________________________________
B. Lectura rápida del comportamiento
[ ] El workflow principal de la hipótesis mejoró
[ ] El número medio de llamadas bajó / subió / quedó igual
[ ] Los 4xx bajaron / subieron / quedaron igual
[ ] Los unsupported bajaron / subieron / quedaron igual
[ ] El tiempo medio bajó / subió / quedó igual
________________________________________
C. Diagnóstico
[ ] Sabemos si el cambio ayudó
[ ] Sabemos si el cambio dañó otra parte
[ ] Sabemos cuál fue el principal patrón de error
[ ] Sabemos si el problema siguiente es parser, payload o eficiencia
________________________________________
D. Decisión
[ ] KEEP
[ ] REVERT
[ ] KEEP + PATCH
Regla útil
•	score sube y logs son más limpios → KEEP
•	score baja y aparecen errores nuevos claros → REVERT
•	score sube un poco pero hay un fallo claro corregible → KEEP + PATCH
________________________________________
6. Plantilla post-submission completa
Copiad esto tal cual:
Submission ID:
Date / Time:
Version Tag:

Main Hypothesis:
Expected Signal:
Actual Score:
Status: better / same / worse

What improved:
- 
- 
- 

What regressed:
- 
- 
- 

Key log signals:
1. 
2. 
3. 

Top failing workflow:
Top failing language:
Top failing endpoint:
Average api_call_count:
422 count:
404 count:
Unsupported rate:

Root cause hypothesis:
Next single change:
Decision: KEEP / REVERT / KEEP + PATCH
________________________________________
7. Dashboard mínimo para decidir el siguiente cambio
Cuando acabéis una submission, responded solo estas 5 preguntas:
1. ¿Estamos entrando al workflow correcto?
Si no:
•	siguiente cambio = parser/router
2. ¿El payload falla con 422?
Si sí:
•	siguiente cambio = payload exacto / tipos / campos
3. ¿Estamos gastando demasiadas llamadas?
Si sí:
•	siguiente cambio = planner / verify / duplicate checks
4. ¿Falla solo en idiomas concretos?
Si sí:
•	siguiente cambio = parser multilingüe
5. ¿Falla sobre todo invoice/project?
Si sí:
•	siguiente cambio = ese workflow, no el resto
________________________________________
8. Táctica diaria recomendada
Si tenéis 3 submissions
Submission 1
Baseline sólida.
Objetivo:
•	asegurar puntuación base
•	confirmar que no se ha roto nada
Submission 2
Cambio con mayor retorno esperado.
Normalmente:
•	invoice
•	parser multilingüe
•	project
Submission 3
Patch pequeño guiado por logs.
Ejemplos:
•	corregir invoiceDueDate
•	ajustar extracción de customer_name
•	quitar un GET sobrante
•	restaurar un lookup que eliminasteis demasiado pronto
________________________________________
Si vais con cautela
Submission 1
baseline
Submission 2
mejora principal
Guardad la tercera para cuando los logs os den una señal muy clara.
________________________________________
9. Priorización de cambios durante el campeonato
Usad esta matriz rápida:
Cambio                         Impacto Esperado   Riesgo   Tiempo   Prioridad
invoice payload/order flow
parser multilingüe
project linkage
remove verify GETs
customer/product simple cleanup
retry tweak
new workflow family
big refactor
Regla
Priorizad cambios con:
•	alto impacto
•	riesgo controlado
•	tiempo corto
•	señal clara en logs
________________________________________
10. Plantilla de “war room” durante el campeonato
Esto os puede servir en una hoja compartida:
CURRENT BEST VERSION:
CURRENT BEST SCORE:
TODAY’S SUBMISSIONS LEFT:

MAIN PROBLEM RIGHT NOW:
MAIN WORKFLOW TO FIX:
MAIN LANGUAGE TO FIX:
MAIN ERROR TYPE:

NEXT SUBMISSION HYPOTHESIS:
EXPECTED LOG SIGNAL:
ROLLBACK PLAN:
OWNER:
STATUS:
Ejemplo
CURRENT BEST VERSION: tripletex-pack5-invoice-order
CURRENT BEST SCORE: 0.61
TODAY’S SUBMISSIONS LEFT: 2

MAIN PROBLEM RIGHT NOW: German/French invoice prompts unsupported
MAIN WORKFLOW TO FIX: create_invoice
MAIN LANGUAGE TO FIX: de/fr
MAIN ERROR TYPE: Unsupported task

NEXT SUBMISSION HYPOTHESIS: multilingual parser fix will reduce unsupported rate
EXPECTED LOG SIGNAL: workflow_selected=create_invoice more often on de/fr prompts
ROLLBACK PLAN: revert parser keyword table
OWNER: Ignacio + Cursor
STATUS: ready
________________________________________
11. Prompt para Cursor — dashboard summary en logs
Pégale esto a Cursor:
Add a lightweight competition dashboard summary log to the Tripletex agent.

Requirements:
- after each /solve, emit one structured summary log with:
  - request_id
  - workflow_name
  - task_type
  - detected_language
  - result_success
  - api_call_count
  - elapsed_ms
  - 4xx_error_count
  - retry_used
  - verification_skipped
  - assume_fresh_account
  - invoice_order_flow_used
- keep it concise and Cloud Run friendly
- do not log secrets
- make the output easy to aggregate in a spreadsheet or log explorer
________________________________________
12. Prompt para Cursor — exportable daily summary
Create a small utility that aggregates structured Cloud Run logs into a daily competition summary.

Requirements:
- group by submission_tag
- compute:
  - request count
  - success rate
  - unsupported rate
  - avg api_call_count
  - avg elapsed_ms
  - 4xx count
  - 404 count
  - 422 count
  - top failing workflow
  - top failing language
- output JSON and CSV
- keep it simple and local-first
________________________________________
13. Reglas de oro durante el campeonato
Regla 1
No subáis una versión que no sepáis explicar en una frase.
Regla 2
No gastéis una submission solo para “ver qué pasa”.
Regla 3
Si el score cae y los logs empeoran, revertid rápido.
Regla 4
Si el score sube pero el cambio es difícil de explicar, mirad logs antes de tocar nada.
Regla 5
Invoice > parser > project suele ser el mejor orden de retorno.
Eso encaja bastante con la estructura del reto y con la complejidad típica de estas tareas. 
________________________________________
14. Mi recomendación práctica final
Durante el campeonato, trabajad así:
•	una hoja viva con este dashboard,
•	una checklist pre,
•	una checklist post,
•	y una sola hipótesis por submission.
Eso os va a dar más puntos que intentar programar “más cosas” sin método.
Si quieres, en el siguiente mensaje te lo convierto en un formato listo para pegar en Notion o Google Docs, ya maquetado como plantilla de trabajo diaria.

...
Ignacio: Si gracias, en el siguiente mensaje conviertelo en un formato listo para pegar en Notion o Google Docs, ya maquetado como plantilla de trabajo diaria.

Perfecto. Aquí tienes la versión lista para pegar en Notion o Google Docs, ya maquetada como plantilla de trabajo diaria para el campeonato, centrada en Tripletex.
Puedes copiarla tal cual.
Está pensada para usarla cada día y también después de cada submission.
________________________________________
AI_NM_2026 – Tripletex
Daily Operations Template
________________________________________
1. Daily Overview
Date:
Team members active today:
Current best version:
Current best score:
Submissions remaining today:
Main goal for today:
Main workflow to improve today:
Main language to improve today:
Main error type to reduce today:
________________________________________
2. Current Competition Status
Best known stable version
Version tag:
Score:
Why it is currently the best:
Most recent submission
Version tag:
Score:
Status: Better / Same / Worse
Keep / Revert / Keep + Patch:
Main problem right now
Problem statement in one sentence:
Example:
“German and French invoice prompts are often routed incorrectly, increasing unsupported rate.”
________________________________________
3. Today’s Submission Plan
Submission 1
Type: Safe baseline / Main improvement / Patch
Version tag:
Main hypothesis:
Expected signal in logs:
Main workflow affected:
Rollback plan:
Submission 2
Type: Safe baseline / Main improvement / Patch
Version tag:
Main hypothesis:
Expected signal in logs:
Main workflow affected:
Rollback plan:
Submission 3
Type: Safe baseline / Main improvement / Patch
Version tag:
Main hypothesis:
Expected signal in logs:
Main workflow affected:
Rollback plan:
________________________________________
4. Pre-Submission Checklist
Submission target
•	This submission has one clear main hypothesis
•	The hypothesis is written in one sentence
•	We know what signal should improve
•	We know what would count as failure
•	We know whether we will KEEP, REVERT, or PATCH depending on result
Scope control
•	Only one main area was changed
•	We did not mix a refactor with a major functional change
•	We did not change deployment unnecessarily
•	Logging still emits the key fields
•	Retry behavior is still controlled and limited
Functional checks
•	pytest passes
•	/health works locally
•	/solve works locally
•	Parser recognizes the changed prompt pattern
•	Router selects the correct workflow
•	Planner behavior still makes sense
•	No secrets are logged
Workflow smoke tests
•	create_employee
•	create_customer
•	create_product
•	create_project
•	create_invoice
Efficiency checks
•	Simple create flows still use minimal calls
•	Project flow does not over-search
•	Invoice flow uses the intended order
•	Verification GETs were not added unnecessarily
•	Expected API call count is still reasonable
________________________________________
5. Submission Record
Submission ID
Submission number:
Date / Time:
Version tag:
Owner:
Main hypothesis
What this submission is testing:
Expected impact
Expected score effect:
Expected log effect:
Expected workflow effect:
________________________________________
6. Post-Submission Review
Raw result
Score:
Status: Better / Same / Worse
Decision: KEEP / REVERT / KEEP + PATCH
What improved
•	
•	
•	
What regressed
•	
•	
•	
Key log signals
1.	
2.	
3.	
Root cause hypothesis
Most likely reason for the observed result:
Next single change
One thing to do next:
________________________________________
7. Submission Analysis Card
Submission ID:
Version tag:
Main hypothesis:
Expected signal:
Actual result:
Decision: KEEP / REVERT / KEEP + PATCH
Metrics
Success rate:
Unsupported rate:
Average API call count:
Average elapsed time (ms):
4xx count:
404 count:
422 count:
Retry used %:
Failure hotspots
Top failing workflow:
Top failing language:
Top failing endpoint:
Top failing error type:
Interpretation
Did the change help?
Did it break something else?
What is the clearest next move?
________________________________________
8. Dashboard – Operational Metrics
Global metrics
Total solve requests:
Success rate:
Unsupported rate:
Average api_call_count:
Average elapsed_ms:
4xx count:
404 count:
422 count:
Retry used %:
Verification skipped %:
Fresh-account assumption used %:
Readout
What these numbers suggest today:
________________________________________
9. Dashboard – Workflow Heatmap
Workflow	Requests	Success %	Avg Calls	4xx	Avg ms	Confidence	Priority
create_employee							
create_customer							
create_product							
create_project							
create_invoice							
delete_travel_expense							
register_payment							
correction/reverse							
unsupported							
Interpretation
Which workflow should we prioritize next and why?
________________________________________
10. Dashboard – Language Coverage
Language	Requests	Success %	Unsupported %	Top Failed Task	Notes
en					
es					
nb					
nn					
pt					
de					
fr					
unknown					
Interpretation
Which language needs parser work next?
________________________________________
11. Dashboard – Error Taxonomy
Error Type	Count	Top Workflow	Most Likely Cause	Action
Unsupported task				
TripletexValidationError 400				
TripletexValidationError 422				
TripletexNotFoundError				
TripletexApiError 404				
Timeout / near-timeout				
Retry failed				
Unexpected exception				
Interpretation
What is the main error family today?
________________________________________
12. Log Review Template
First look
•	Workflow selected correctly
•	Intent parsed correctly
•	Language detected correctly
•	API call order makes sense
•	Retry behavior is reasonable
•	No extra verification calls
•	No duplicate POSTs
•	No secrets logged
Key signals
Top good signal:
Top bad signal:
Most suspicious log pattern:
Log-based next action
Parser / Workflow / Payload / Planner / Retry / Efficiency
________________________________________
13. Decision Matrix for Next Change
If we see this…
Many unsupported tasks
→ Improve parser / router
Many 422 errors
→ Fix payload structure, field names, numeric/date normalization
Many 404 errors
→ Fix endpoint path or workflow order
Score flat but calls high
→ Reduce GETs and unnecessary verification
One language much worse than others
→ Improve multilingual parser
Invoice failing most often
→ Focus next submission on invoice only
Project failing with customer linkage
→ Focus next submission on project payload / customer lookup
________________________________________
14. Prioritization Table
Possible Change	Expected Impact	Risk	Time	Priority
Invoice payload / order flow	High	Medium	Medium	
Multilingual parser	High	Medium	Medium	
Project linkage	Medium	Medium	Low	
Remove unnecessary GET verification	Medium	Low	Low	
Customer / product simple cleanup	Medium	Low	Low	
Retry tweak	Low / Medium	Medium	Low	
New workflow family	Variable	High	High	
Big refactor	Low immediate	High	High	
Decision
What change gives the best return right now?
________________________________________
15. War Room Block
CURRENT BEST VERSION:
CURRENT BEST SCORE:
SUBMISSIONS LEFT TODAY:
MAIN PROBLEM RIGHT NOW:
MAIN WORKFLOW TO FIX:
MAIN LANGUAGE TO FIX:
MAIN ERROR TYPE:
NEXT SUBMISSION HYPOTHESIS:
EXPECTED LOG SIGNAL:
ROLLBACK PLAN:
OWNER:
STATUS: Ready / In progress / Blocked
________________________________________
16. Quick End-of-Day Summary
Best score today:
Best version today:
Worst failure today:
Biggest lesson learned today:
Most valuable log signal today:
Main workflow to attack tomorrow:
Main language to attack tomorrow:
What we will not touch tomorrow:
________________________________________
17. One-Line Rule of the Day
Today’s rule:
Example:
“Only one meaningful hypothesis per submission.”
________________________________________
18. Daily Notes
•	
•	
•	
•	
________________________________________
19. Ultra-short Match Version
Si queréis una versión rapidísima para usar bajo presión, copiad también esta:
Before submission
•	One hypothesis
•	One main area changed
•	Tests passed
•	Local smoke test passed
•	Expected log signal defined
•	Rollback plan defined
After submission
•	Score recorded
•	Better / Same / Worse marked
•	Top failing workflow identified
•	Top failing language identified
•	Main error type identified
•	Next single change chosen
•	Keep / Revert / Patch decided
________________________________________
Si quieres, te preparo también una segunda versión todavía más visual, pensada específicamente para Notion con encabezados, callouts y tablas más limpias.


Ignacio Tejera
Mars 2026




