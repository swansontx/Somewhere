from apscheduler.schedulers.background import BackgroundScheduler
from app.services.worker import recompute_projections
import logging

log = logging.getLogger(__name__)

sched = BackgroundScheduler()

# Example: run recompute every 15 minutes
sched.add_job(recompute_projections, 'interval', minutes=15, id='recompute_projections')


def start():
    log.info('Starting scheduler...')
    sched.start()


def shutdown():
    sched.shutdown()
