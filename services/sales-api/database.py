import os
import uuid
from sqlalchemy import create_engine, Column, String, Integer, DateTime, ARRAY, Text
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.sql import func

POSTGRES_HOST     = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT     = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB       = os.getenv("POSTGRES_DB", "sales_db")
POSTGRES_USER     = os.getenv("POSTGRES_USER", "sales_user")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "changeme")

DATABASE_URL = (
    f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
    f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
)

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Customer(Base):
    __tablename__ = "customers"
    id         = Column(String, primary_key=True)
    name       = Column(String, nullable=False)
    email      = Column(String)
    phone      = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Order(Base):
    __tablename__ = "orders"
    id             = Column(String, primary_key=True)
    order_number   = Column(String, unique=True, nullable=False)
    customer_id    = Column(String, nullable=False)
    payment_method = Column(String, nullable=False)
    status         = Column(String, nullable=False, default="pending")
    created_at     = Column(DateTime(timezone=True), server_default=func.now())
    updated_at     = Column(DateTime(timezone=True), server_default=func.now())


class OrderItem(Base):
    __tablename__ = "order_items"
    id           = Column(String, primary_key=True)
    order_id     = Column(String, nullable=False)
    product_id   = Column(String, nullable=False)
    product_name = Column(String, nullable=False)
    quantity     = Column(Integer, nullable=False)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())


class ErrorReport(Base):
    __tablename__ = "error_reports"
    id           = Column(String, primary_key=True)
    order_number = Column(String)
    reported_by  = Column(String, nullable=False)
    issue_type   = Column(String, nullable=False)
    description  = Column(Text, nullable=False)
    notify_teams = Column(ARRAY(Text))
    status       = Column(String, nullable=False, default="open")
    created_at   = Column(DateTime(timezone=True), server_default=func.now())


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
