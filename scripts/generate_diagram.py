"""Generates docs/architecture.drawio for the Customer Service Bot project using drawpyo.

Run with: python3 scripts/generate_diagram.py
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_group(page, name, x, y, width, height):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "rounded=0;whiteSpace=wrap;html=1;dashed=0;fillColor=none;"
        "strokeColor=#146EB4;verticalAlign=top;align=left;fontColor=#146EB4;fontSize=12;"
        "spacingLeft=6;spacingTop=4;"
    )
    return group


def add_edge(page, source, target, label=None, bidirectional=False):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "block" if bidirectional else "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Customer Service Bot"

    aws_cloud = add_group(page, "AWS Cloud", 40, 40, 900, 560)

    end_users = add_node(page, "End users", 40, 300, "client", "#232F3E")
    web_app = add_node(page, "Web application", 200, 300, "client", "#232F3E")
    access_ai = add_node(page, "Access AI models", 380, 300, "machine_learning", "#01A88D")
    foundation_model = add_node(page, "Foundation model", 380, 460, "machine_learning", "#01A88D")
    perform_actions = add_node(page, "Perform actions", 380, 100, "lambda_function", "#ED7100")

    action_group = add_group(page, "Action groups", 540, 80, 240, 460)
    data_storage = add_node(page, "Data storage\n(OpenAPI schema)", 590, 130, "bucket", "#7AA116")
    action_handler = add_node(page, "Place order\nCheck inventory\nCheck customer\ndetails and traits", 590, 380, "lambda_function", "#ED7100")

    access_permissions = add_node(page, "Access\npermissions", 840, 130, "identity_and_access_management_iam", "#DD344C")
    store_password = add_node(page, "Store database\npassword", 980, 130, "secrets_manager", "#DD344C")

    customer_database = add_node(page, "Customer\ndatabase", 980, 380, "dynamodb", "#C925D1")

    add_edge(page, end_users, web_app, "Request / Response", bidirectional=True)
    add_edge(page, web_app, access_ai, "Request / Response", bidirectional=True)
    add_edge(page, access_ai, perform_actions, "Create alias", bidirectional=True)
    add_edge(page, access_ai, foundation_model, bidirectional=True)
    add_edge(page, perform_actions, action_handler, "Invoke / Response")
    add_edge(page, action_handler, data_storage, "Load database")
    add_edge(page, action_handler, customer_database, "Request data / Response", bidirectional=True)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
