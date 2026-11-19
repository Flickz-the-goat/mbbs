import csv, random, json, pickle
from pathlib import Path
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error
from sklearn.model_selection import train_test_split
p=Path(__file__).resolve().parent
rng=random.Random(42)
rows=[]
for i in range(3000):
    level=rng.randint(1,8); size=rng.randint(1,7); children=rng.randint(0,max(0,size-1)); seniors=rng.randint(0,size-children)
    rice=round(rng.uniform(0,8),2); beans=round(rng.uniform(0,5),2); cans=rng.randint(0,18); water=round(rng.uniform(0,35),1)
    daily=round(rng.uniform(1.6,2.5),2); days=rng.randint(1,7); reserve=round(rng.uniform(0,2),1)
    # Artificial target: daily food portions adjusted for composition and expected consumption,
    # minus reported available food converted to portion-equivalents. Not a nutrition standard.
    required=days*(size*daily + children*.25 + seniors*.15)
    on_hand=rice*2.4+beans*3+cans*.8
    target=round(max(0,required-on_hand+reserve*size),2)
    rows.append([f'HH{i+1:05d}',level,size,children,seniors,rice,beans,cans,water,daily,days,reserve,target])
cols=['household_id','level_id','household_size','children_count','senior_count','rice_kg','beans_kg','canned_food_count','water_liters','daily_portions_per_person','planning_days','reserve_portions_per_person','additional_ration_units_needed']
with (p/'households.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(cols);w.writerows(rows)
features=cols[1:-1]; X=np.array([r[1:-1] for r in rows],dtype=float); y=np.array([r[-1] for r in rows]);
# Independent holdout; synthetic data, metrics measure learning a synthetic rule only.
Xtr,Xte,ytr,yte=train_test_split(X,y,test_size=.2,random_state=42)
model=RandomForestRegressor(n_estimators=160,min_samples_leaf=2,max_features=1.0,n_jobs=-1,random_state=42)
model.fit(Xtr,ytr)
with (p/'ration_demand_model.pkl').open('wb') as f:pickle.dump({'model':model,'features':features,'units':'synthetic portion equivalents'},f)
metrics={'training_rows':len(Xtr),'test_rows':len(Xte),'test_mae_ration_units':round(float(mean_absolute_error(yte,model.predict(Xte))),3),'warning':'Synthetic targets generated from a formula; this does not validate real-world food needs or nutrition.'}
(p/'metrics.json').write_text(json.dumps(metrics,indent=2))
# Aggregate per level: submitted vs voluntarily pledged, to avoid treating private food as redistributable.
with (p/'level_inventory.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['level_id','population','shared_ration_units','distribution_center_capacity_per_hour','pickup_open_hour','pickup_close_hour'])
 for level in range(1,9):
  people=sum(r[2] for r in rows if r[1]==level)
  w.writerow([level,people,rng.randint(100,600),rng.randint(20,60),9,17])
with (p/'food_submissions.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['submission_id','household_id','level_id','food_type','quantity','unit','is_pledged_for_distribution','photo_path','verification_status'])
 for idx,r in enumerate(rows[:150],1):
  w.writerow([f'S{idx:05d}',r[0],r[1],'rice',r[5],'kg',rng.choice([False,False,True]),f'photos/{r[0]}.jpg','pending'])
print(metrics)
