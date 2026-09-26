import os
import socket

import pymysql
from flask import Flask, jsonify, request

app = Flask(__name__)


def get_conn():
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        connect_timeout=5,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )


def init_db():
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "CREATE TABLE IF NOT EXISTS orders ("
            "id INT AUTO_INCREMENT PRIMARY KEY, "
            "customer VARCHAR(100) NOT NULL, "
            "item VARCHAR(100) NOT NULL, "
            "quantity INT NOT NULL, "
            "status VARCHAR(20) NOT NULL DEFAULT 'CREATED', "
            "created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
        )
    conn.close()


init_db()


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/")
def info():
    return jsonify(
        service="orderhub",
        env=os.environ["APP_ENV"],
        version=os.environ["APP_VERSION"],
        host=socket.gethostname(),
    )


@app.post("/api/orders")
def create_order():
    data = request.get_json(silent=True) or {}
    customer = str(data.get("customer", "")).strip()
    item = str(data.get("item", "")).strip()
    quantity = data.get("quantity")
    if not customer or not item or type(quantity) is not int or quantity <= 0:
        return jsonify(error="customer, item and positive integer quantity are required"), 400
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO orders (customer, item, quantity) VALUES (%s, %s, %s)",
            (customer, item, quantity),
        )
        order_id = cur.lastrowid
    conn.close()
    return jsonify(id=order_id, status="CREATED"), 201


@app.get("/api/orders")
def list_orders():
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM orders ORDER BY id DESC LIMIT 50")
        rows = cur.fetchall()
    conn.close()
    return jsonify(rows)


@app.get("/api/orders/<int:order_id>")
def get_order(order_id):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM orders WHERE id = %s", (order_id,))
        row = cur.fetchone()
    conn.close()
    if row is None:
        return jsonify(error="order not found"), 404
    return jsonify(row)
