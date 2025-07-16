# ======================
# 1. IMPORTS (Grouped by functionality)
# ======================
# Standard library
from datetime import datetime
import io
import json
import logging
import os
import uuid
from pathlib import Path
from typing import Dict, List, Optional
from concurrent.futures import ThreadPoolExecutor 
import asyncio

# Third-party
import librosa
import numpy as np
import tensorflow as tf
import logging
from fastapi import FastAPI, File, UploadFile, HTTPException, Request, Body, status, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, field_validator
from sklearn.preprocessing import LabelEncoder
from sqlalchemy import Column, String, Float, DateTime, select, delete
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.exc import SQLAlchemyError 
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from fastapi import Form  
import base64

# ======================
# 1.1 Logger
# ======================
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ======================
# 2. CONFIGURATION CLASS
# ======================
class Config:
    MODEL_PATH = Path("catsound_class.keras")
    LABEL_ENCODER_PATH = Path("label_encoder.json")
    CAT_DETECTOR_MODEL_PATH = Path("../Model_Detection/cat_detector.keras")
    CAT_DETECTOR_LABEL_ENCODER_PATH = Path("../Model_Detection/cat_detector_label_encoder.json")
    MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
    BASE_DIR = Path(__file__).parent.absolute()  # Get the directory where main.py is located
    STATIC_DIR = BASE_DIR / "static"
    AUDIO_DIR = STATIC_DIR / "audio"
    
    # Initialize directories
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)

executor = ThreadPoolExecutor(max_workers=4)

# ======================
# 3. DATABASE SETUP
# ======================
Base = declarative_base()

class Prediction(Base):
    __tablename__ = "predictions"
    id = Column(String, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow)
    filename = Column(String)
    prediction = Column(String)
    confidence = Column(Float)

# Database engine (async)
SQLALCHEMY_DATABASE_URL = "sqlite+aiosqlite:///./predictions.db"
engine = create_async_engine(SQLALCHEMY_DATABASE_URL)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

# ======================
# 4. PYDANTIC MODELS (Request/Response)
# ======================
class DeleteRequest(BaseModel):
    ids: List[str] 

class PredictionResponse(BaseModel):
    success: bool
    cat_detected: bool
    cat_detector_prediction: str
    cat_detector_confidence: float
    cat_sound_prediction: Optional[str] = None
    cat_sound_confidence: Optional[float] = None
    audio_url: str
    probabilities: Dict[str, float]
    cat_sound_probabilities: Optional[Dict[str, float]] = None

class HistoryResponse(BaseModel):
    id: str
    timestamp: Optional[str] = None
    filename: str
    prediction: str
    confidence: float
    audio_url: str

# ======================
# 5. CORE FUNCTIONALITY
# ======================
# ---- 5.1 Audio Preprocessing ----
def process_audio_file(audio_data: bytes) -> np.ndarray:
    """Convert raw audio to Mel spectrogram"""
    try:
        if len(audio_data) == 0:
            raise ValueError("Empty audio data received")

        audio_stream = io.BytesIO(audio_data)
        audio, sr = librosa.load(audio_stream, sr=22050)
        
        if len(audio) == 0:
            raise ValueError("No audio data after loading")
        
        mel_spec = librosa.feature.melspectrogram(y=audio, sr=sr, n_mels=64, hop_length=512)
        mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)
        
        max_pad_len = 105
        if mel_spec_db.shape[1] > max_pad_len:
            mel_spec_db = mel_spec_db[:, :max_pad_len]
        else:
            pad_width = max_pad_len - mel_spec_db.shape[1]
            mel_spec_db = np.pad(mel_spec_db, ((0, 0), (0, pad_width)), mode='edge')
        
        # Check for invalid values before normalization
        if np.isnan(mel_spec_db).any() or np.isinf(mel_spec_db).any():
            raise ValueError("Invalid values in mel spectrogram")
        
        mel_spec_db = (mel_spec_db - np.mean(mel_spec_db)) / np.std(mel_spec_db)
        return mel_spec_db.T[np.newaxis, ..., np.newaxis]
    
    except Exception as e:
        logger.error(f"Audio processing failed: {str(e)}")
        raise ValueError(f"Audio processing error: {str(e)}")

def process_realtime_audio(audio_data: bytes) -> np.ndarray:
    """Convert raw audio to Mel spectrogram for realtime mode with PCM format"""
    try:
        if len(audio_data) == 0:
            raise ValueError("Empty audio data received")

        # Convert bytes to numpy array assuming 16-bit PCM
        audio = np.frombuffer(audio_data, dtype=np.int16)
        # Convert to float32 and normalize
        audio = audio.astype(np.float32) / 32768.0
        sr = 48000  # Device's sample rate
        
        if len(audio) == 0:
            raise ValueError("No audio data after loading")
        
        mel_spec = librosa.feature.melspectrogram(y=audio, sr=sr, n_mels=64, hop_length=512)
        mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)
        
        max_pad_len = 105
        if mel_spec_db.shape[1] > max_pad_len:
            mel_spec_db = mel_spec_db[:, :max_pad_len]
        else:
            pad_width = max_pad_len - mel_spec_db.shape[1]
            mel_spec_db = np.pad(mel_spec_db, ((0, 0), (0, pad_width)), mode='edge')
        
        # Check for invalid values before normalization
        if np.isnan(mel_spec_db).any() or np.isinf(mel_spec_db).any():
            raise ValueError("Invalid values in mel spectrogram")
        
        mel_spec_db = (mel_spec_db - np.mean(mel_spec_db)) / np.std(mel_spec_db)
        return mel_spec_db.T[np.newaxis, ..., np.newaxis]
    
    except Exception as e:
        logger.error(f"Realtime audio processing failed: {str(e)}")
        raise ValueError(f"Realtime audio processing error: {str(e)}")

def save_audio_file(filename: str, audio_data: bytes) -> str:
    """Save audio to disk with original filename, handling duplicates"""
    try:
        # Sanitize the filename to remove any path components
        original_filename = Path(filename).name
        
        # Create a version counter for duplicates
        counter = 1
        base_name, ext = os.path.splitext(original_filename)
        save_path = Config.AUDIO_DIR / original_filename
        
        # Handle duplicate filenames by adding (1), (2), etc.
        while save_path.exists():
            new_filename = f"{base_name} ({counter}){ext}"
            save_path = Config.AUDIO_DIR / new_filename
            counter += 1
        
        with open(save_path, 'wb') as f:
            f.write(audio_data)
            
        return save_path.name  # Return just the filename part
    
    except Exception as e:
        logger.error(f"Failed to save audio file: {str(e)}")
        raise

# ---- 5.2 Model Loading ----
def load_model_assets(model_path, label_encoder_path):
    """Load TF model and label encoder"""
    try:
        if not model_path.exists():
            raise FileNotFoundError(f"Model file not found at {model_path}")
        if not label_encoder_path.exists():
            raise FileNotFoundError(f"Label encoder file not found at {label_encoder_path}")

        model = tf.keras.models.load_model(model_path)
        model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
        
        with open(label_encoder_path, "r") as f:
            label_encoder_classes = json.load(f)
        
        label_encoder = LabelEncoder()
        label_encoder.classes_ = np.array(label_encoder_classes)
        
        return model, label_encoder
    
    except Exception as e:
        logger.error(f"Failed to load model assets: {str(e)}")
        raise

try:
    # Load cat detector model and label encoder
    cat_detector_model, cat_detector_label_encoder = load_model_assets(
        Config.CAT_DETECTOR_MODEL_PATH, Config.CAT_DETECTOR_LABEL_ENCODER_PATH
    )
    # Load cat sound classifier model and label encoder
    cat_sound_model, cat_sound_label_encoder = load_model_assets(
        Config.MODEL_PATH, Config.LABEL_ENCODER_PATH
    )
except Exception as e:
    logger.critical(f"Application startup failed: {str(e)}")
    raise

# ======================
# 6. FASTAPI APP SETUP
# ======================
app = FastAPI(
    title="Cat Sound Classifier API",
    description="API for classifying cat sounds",
    version="1.0.0"
)

@app.on_event("startup")
async def startup_event():
    await init_db()

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static files and templates
app.mount("/static", StaticFiles(directory=str(Config.STATIC_DIR)), name="static")
templates = Jinja2Templates(directory="templates")

# Add explicit route for audio files
@app.get("/static/audio/{filename}")
async def get_audio_file(filename: str):
    try:
        file_path = Config.AUDIO_DIR / filename
        logger.info(f"Attempting to serve audio file from: {file_path}")
        if not file_path.exists():
            logger.error(f"Audio file not found at: {file_path}")
            raise HTTPException(status_code=404, detail="Audio file not found")
        return FileResponse(str(file_path), media_type="audio/wav")
    except Exception as e:
        logger.error(f"Error serving audio file {filename}: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

# ======================
# 7. API ENDPOINTS
# ======================
@app.post("/predict", response_model=PredictionResponse)
async def predict(
    file: UploadFile = File(...),
    file_id: str = Form(None) 
):
    try:
        # Validate file size
        file.file.seek(0, 2)
        file_size = file.file.tell()
        file.file.seek(0)
        
        if file_size > Config.MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"File too large. Max size: {Config.MAX_FILE_SIZE/1024/1024}MB"
            )

        audio_data = await file.read()
        
        # Generate file_id if not provided from frontend
        if not file_id:
            file_id = str(uuid.uuid4())  # Fallback to UUID if missing
        
        # Offload processing to thread pool
        features = await asyncio.get_event_loop().run_in_executor(
            executor,
            process_audio_file,
            audio_data
        )
        
        # --- Stage 1: Cat Detector ---
        cat_detector_proba = await asyncio.get_event_loop().run_in_executor(
            executor,
            lambda: cat_detector_model.predict(features)[0]
        )
        cat_detector_pred_class = np.argmax(cat_detector_proba)
        cat_detector_class_name = cat_detector_label_encoder.inverse_transform([cat_detector_pred_class])[0]
        cat_detector_confidence = float(cat_detector_proba.max())
        cat_detected = cat_detector_class_name == "cat"
        
        # Save audio file 
        saved_filename = save_audio_file(file.filename, audio_data)
        audio_url = f"/static/audio/{saved_filename}"
        
        # --- Stage 2: Cat Sound Classifier (only if cat detected) ---
        cat_sound_prediction = None
        cat_sound_confidence = None
        cat_sound_probabilities = None
        if cat_detected:
            cat_sound_proba = await asyncio.get_event_loop().run_in_executor(
                executor,
                lambda: cat_sound_model.predict(features)[0]
            )
            cat_sound_pred_class = np.argmax(cat_sound_proba)
            cat_sound_class_name = cat_sound_label_encoder.inverse_transform([cat_sound_pred_class])[0]
            cat_sound_confidence = float(cat_sound_proba.max())
            cat_sound_prediction = cat_sound_class_name
            cat_sound_probabilities = {label: float(prob) for label, prob in zip(cat_sound_label_encoder.classes_, cat_sound_proba)}
        
        # Store prediction in database (with file_id)
        async with AsyncSessionLocal() as db:
            db_prediction = Prediction(
                id=file_id,  
                filename=saved_filename,
                prediction=cat_detector_class_name if not cat_detected else cat_sound_prediction,
                confidence=cat_detector_confidence if not cat_detected else cat_sound_confidence
            )
            db.add(db_prediction)
            await db.commit()
        
        return {
            "success": True,
            "cat_detected": cat_detected,
            "cat_detector_prediction": cat_detector_class_name,
            "cat_detector_confidence": cat_detector_confidence,
            "cat_sound_prediction": cat_sound_prediction,
            "cat_sound_confidence": cat_sound_confidence,
            "audio_url": audio_url,
            "probabilities": {label: float(prob) for label, prob in zip(cat_detector_label_encoder.classes_, cat_detector_proba)},
            "cat_sound_probabilities": cat_sound_probabilities
        }
    
    except Exception as e:
        logger.error(f"Prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")
    
@app.get("/api/history", response_model=List[HistoryResponse])
async def get_history(limit: int = 10):
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(Prediction)
                .order_by(Prediction.timestamp.desc())
                .limit(limit)
            )
            history = result.scalars().all()
            
            return [{
                "id": item.id,
                "timestamp": item.timestamp.isoformat(),
                "filename": item.filename,
                "prediction": item.prediction,
                "confidence": item.confidence,
                "audio_url": f"/static/audio/{item.filename}"  
            } for item in history]
        
    except SQLAlchemyError as e:
        logger.error(f"Database error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database error"
        )

@app.delete("/api/history/delete")
async def delete_history(request: DeleteRequest):
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                delete(Prediction)
                .where(Prediction.id.in_(request.ids))
                .returning(Prediction.id)
            )
            deleted_ids = result.scalars().all()
            await db.commit()
            
            if not deleted_ids:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="No matching records found"
                )
            
            return {
                "success": True,
                "deleted_count": len(deleted_ids),
                "message": f"Deleted {len(deleted_ids)} items"
            }
    except SQLAlchemyError as e:
        await db.rollback()
        logger.error(f"Delete operation failed: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database error during deletion"
        )

@app.websocket("/ws/realtime_predict")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            # Receive audio data from client
            data = await websocket.receive_text()
            
            # Decode base64 audio data
            try:
                audio_bytes = base64.b64decode(data)
                # Process audio chunk
                features = process_audio_file(audio_bytes)
                
                # --- Stage 1: Cat Detector ---
                cat_detector_proba = cat_detector_model.predict(features)[0]
                cat_detector_pred_class = np.argmax(cat_detector_proba)
                cat_detector_class_name = cat_detector_label_encoder.inverse_transform([cat_detector_pred_class])[0]
                cat_detector_confidence = float(cat_detector_proba.max())
                cat_detected = cat_detector_class_name == "cat"

                if not cat_detected:
                    await websocket.send_json({
                        "success": True,
                        "cat_detected": False,
                        "cat_detector_prediction": cat_detector_class_name,
                        "cat_detector_confidence": cat_detector_confidence,
                        "message": "Not a cat sound"
                    })
                    continue

                # --- Stage 2: Cat Sound Classifier ---
                proba = cat_sound_model.predict(features)[0]
                pred_class = np.argmax(proba)
                class_name = cat_sound_label_encoder.inverse_transform([pred_class])[0]
                confidence = float(proba.max())
                
                # Send prediction back to client
                await websocket.send_json({
                    "success": True,
                    "cat_detected": True,
                    "cat_detector_prediction": cat_detector_class_name,
                    "cat_detector_confidence": cat_detector_confidence,
                    "prediction": class_name,
                    "confidence": confidence,
                    "probabilities": {label: float(prob) for label, prob in zip(cat_sound_label_encoder.classes_, proba)}
                })
            except Exception as e:
                await websocket.send_json({
                    "success": False,
                    "error": str(e)
                })
    except Exception as e:
        logger.error(f"WebSocket error: {str(e)}")
    finally:
        await websocket.close()

@app.post("/realtime_predict")
async def realtime_predict(
    audio: UploadFile = File(..., description="Audio file to analyze")
):
    try:
        # Validate file size
        audio.file.seek(0, 2)
        file_size = audio.file.tell()
        audio.file.seek(0)
        
        if file_size == 0:
            raise HTTPException(
                status_code=status.HTTP_401_BAD_REQUEST,
                detail="Empty audio file received"
            )
            
        if file_size > Config.MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"File too large. Max size: {Config.MAX_FILE_SIZE/1024/1024}MB"
            )

        audio_data = await audio.read()
        
        # Process audio using realtime processing
        features = await asyncio.get_event_loop().run_in_executor(
            executor,
            process_realtime_audio,  # Use realtime processing
            audio_data
        )
        
        # --- Stage 1: Cat Detector ---
        cat_detector_proba = await asyncio.get_event_loop().run_in_executor(
            executor,
            lambda: cat_detector_model.predict(features)[0]
        )
        cat_detector_pred_class = np.argmax(cat_detector_proba)
        cat_detector_class_name = cat_detector_label_encoder.inverse_transform([cat_detector_pred_class])[0]
        cat_detector_confidence = float(cat_detector_proba.max())
        cat_detected = cat_detector_class_name == "cat"

        if not cat_detected:
            return {
                "success": True,
                "cat_detected": False,
                "cat_detector_prediction": cat_detector_class_name,
                "cat_detector_confidence": cat_detector_confidence,
                "message": "Not a cat sound"
            }

        # --- Stage 2: Cat Sound Classifier ---
        proba = await asyncio.get_event_loop().run_in_executor(
            executor,
            lambda: cat_sound_model.predict(features)[0]
        )
        pred_class = np.argmax(proba)
        class_name = cat_sound_label_encoder.inverse_transform([pred_class])[0]
        confidence = float(proba.max())
        
        return {
            "success": True,
            "cat_detected": True,
            "cat_detector_prediction": cat_detector_class_name,
            "cat_detector_confidence": cat_detector_confidence,
            "prediction": class_name,
            "confidence": confidence,
            "probabilities": {label: float(prob) for label, prob in zip(cat_sound_label_encoder.classes_, proba)}
        }
    
    except ValueError as e:
        logger.error(f"Invalid audio data: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Realtime prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

# ======================
# 8. MAIN APPLICATION
# ======================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)