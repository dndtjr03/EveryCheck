"""커스텀 Swagger UI + multipart binary 형식 패치."""

from fastapi import FastAPI
from fastapi.openapi.docs import (
    get_swagger_ui_html,
    get_swagger_ui_oauth2_redirect_html,
)
from fastapi.openapi.utils import get_openapi


def _patch_file_upload_property(prop: dict) -> None:
    if prop.get("contentMediaType") == "application/octet-stream":
        prop["format"] = "binary"
        return
    items = prop.get("items")
    if isinstance(items, dict) and items.get("contentMediaType") == "application/octet-stream":
        items["format"] = "binary"


def _patch_multipart_file_binary_format(openapi_schema: dict) -> None:
    """로컬 Swagger UI가 multipart file 필드를 file input으로 렌더링하도록 format 추가."""
    schemas = (openapi_schema.get("components") or {}).get("schemas") or {}
    for schema in schemas.values():
        if not isinstance(schema, dict):
            continue
        for key in ("file", "files"):
            prop = schema.get("properties", {}).get(key)
            if isinstance(prop, dict):
                _patch_file_upload_property(prop)


def install_openapi(app: FastAPI) -> None:
    """커스텀 OpenAPI 빌더 및 Swagger UI 라우트를 등록한다."""

    def custom_openapi():
        if app.openapi_schema:
            return app.openapi_schema
        openapi_schema = get_openapi(
            title=app.title,
            version=app.version,
            description=app.description,
            routes=app.routes,
        )
        _patch_multipart_file_binary_format(openapi_schema)
        app.openapi_schema = openapi_schema
        return app.openapi_schema

    app.openapi = custom_openapi  # type: ignore[assignment]

    @app.get("/docs", include_in_schema=False)
    async def swagger_ui_html():
        """Swagger UI — JS/CSS는 로컬 /static 만 사용 (CDN 없음)."""
        return get_swagger_ui_html(
            openapi_url="/openapi.json",
            title=f"{app.title} - Swagger UI",
            swagger_js_url="/static/swagger-ui/swagger-ui-bundle.js",
            swagger_css_url="/static/swagger-ui/swagger-ui.css",
            swagger_favicon_url="/static/swagger-ui/favicon-32x32.png",
            oauth2_redirect_url="/docs/oauth2-redirect",
        )

    @app.get("/docs/oauth2-redirect", include_in_schema=False)
    async def swagger_ui_oauth2_redirect():
        return get_swagger_ui_oauth2_redirect_html()
