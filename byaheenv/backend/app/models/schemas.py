from pydantic import BaseModel

class CountsResponse(BaseModel):
    region_counts: dict
    class_counts: dict