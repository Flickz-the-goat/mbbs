from alembic import context

from app import models
from app.db import database_url, make_engine

version_table = "hollow_alembic_version"

if context.is_offline_mode():
    context.configure(url=database_url(), target_metadata=models.Base.metadata,
                      version_table=version_table, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    with make_engine().connect() as connection:
        context.configure(connection=connection, target_metadata=models.Base.metadata,
                          version_table=version_table)
        with context.begin_transaction():
            context.run_migrations()
