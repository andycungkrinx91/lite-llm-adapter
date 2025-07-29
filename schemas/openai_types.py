from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Union, Any

class ChatMessage(BaseModel):
    """A message in a chat conversation."""
    role: str
    content: str

class ChatCompletionRequest(BaseModel):
    """
    Request model for chat completions, compatible with the OpenAI API.
    """
    messages: List[ChatMessage]
    session_id: Optional[str] = None
    model: Optional[str] = None
    frequency_penalty: Optional[float] = Field(default=0.0, ge=-2.0, le=2.0)
    logit_bias: Optional[Dict[str, float]] = None
    logprobs: Optional[bool] = False
    top_logprobs: Optional[int] = Field(default=None, ge=0, le=20)
    max_tokens: Optional[int] = None
    n: Optional[int] = Field(default=1, ge=1)
    presence_penalty: Optional[float] = Field(default=0.0, ge=-2.0, le=2.0)
    response_format: Optional[Dict[str, Any]] = None
    seed: Optional[int] = None
    stop: Optional[Union[str, List[str]]] = None
    stream: bool = False
    temperature: Optional[float] = Field(default=1.0, ge=0.0, le=2.0)
    top_p: Optional[float] = Field(default=1.0, ge=0.0, le=1.0)
    user: Optional[str] = None

    class Config:
        extra = "ignore"