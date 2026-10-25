# database.py
import os
from sqlalchemy import create_engine, Column, Integer, String, Float, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import sessionmaker, declarative_base, relationship
from datetime import datetime

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./triton.db")
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Victim(Base):
    __tablename__ = "victims"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    device_id = Column(String, unique=True, index=True, nullable=False)
    age_years = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    acknowledged = Column(Boolean, default=False, nullable=False)
    acknowledged_at = Column(DateTime, nullable=True)

    telemetry_readings = relationship(
        "Telemetry", back_populates="victim", cascade="all, delete-orphan"
    )


class Telemetry(Base):
    __tablename__ = "telemetry"

    id = Column(Integer, primary_key=True, index=True)
    victim_id = Column(Integer, ForeignKey("victims.id"), nullable=False)

    bpm = Column(Float, nullable=False)
    piezo_depth = Column(Integer, nullable=False)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    battery_pct = Column(Float, nullable=True)
    sos = Column(Boolean, default=False, nullable=False)
    # LoRa packet loss rate (0.0-1.0) for this device, as tracked by the
    # gateway. NULL until real gateway firmware starts reporting it -
    # currently only populated by the simulator for demo purposes.
    plr = Column(Float, nullable=True)
    timestamp = Column(DateTime, default=datetime.utcnow, index=True)

    victim = relationship("Victim", back_populates="telemetry_readings")


def init_db():
    Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()