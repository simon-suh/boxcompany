import os
import uuid
from sqlalchemy import create_engine, Column, String, Integer, DateTime, ARRAY, Text
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.sql import func

# Use DB_* prefix to avoid conflict with Kubernetes auto-injected POSTGRES_* vars
DB_HOST     = os.getenv("DB_HOST", "localhost")
DB_PORT     = os.getenv("DB_PORT", "5432")
DB_NAME     = os.getenv("DB_NAME", "sales_db")
DB_USER     = os.getenv("DB_USER", "sales_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "changeme")

DATABASE_URL = (
    f"postgresql://{DB_USER}:{DB_PASSWORD}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
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
    id             = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    order_number   = Column(String, unique=True, nullable=False)
    customer_id    = Column(String, nullable=False)
    payment_method = Column(String, nullable=False)
    status         = Column(String, nullable=False, default="pending")
    created_at     = Column(DateTime(timezone=True), server_default=func.now())
    updated_at     = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class OrderItem(Base):
    __tablename__ = "order_items"
    id           = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    order_id     = Column(String, nullable=False)
    product_id   = Column(String, nullable=False)
    product_name = Column(String, nullable=False)
    quantity     = Column(Integer, nullable=False)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

class ErrorReport(Base):
    __tablename__ = "error_reports"
    id           = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    order_number = Column(String)
    reported_by  = Column(String, nullable=False)
    issue_type   = Column(String, nullable=False)
    description  = Column(Text, nullable=False)
    notify_teams = Column(ARRAY(String))
    status       = Column(String, nullable=False, default="open")
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
