set -x
DATE=$(date +%m%d)
TIME_TAG=$(date +%H:%M)

ray stop
# ------------------------------------------------------------------------------------------------
export PYTHONPATH=$ROOT:$PYTHONPATH

export HF_ENDPOINT=https://hf-mirror.com
export no_proxy="127.0.0.1,localhost"
export NO_PROXY="127.0.0.1,localhost"

# Set XFormers backend to avoid CUDA errors
export VLLM_ATTENTION_BACKEND=XFORMERS

source activate uft
# ------------------------------------------------------------------------------------------------
# NOTE: change to your root dir
ROOT=../Unify-Post-Training

# export SWANLAB_API_KEY='xxx' 
export WANDB_PROJECT="unified-ft"

UNIFY_STRATEGY="switch"
SWITCH_GATE=0
SWITCH_GATE_OFF=0 # 对于2阶段的switch：SWITCH_GATE_OFF=SWITCH_GATE
OFFLINE_LOSS_TYPE="sft" # 对于2阶段的switch：off_policy, sft, switch_off_sft（switch_off_sft表示对offline data使用sft和off rl混合loss）
SFT_LOSS_COEF=1.0
REMOVE_SFTED_DATA=False # 置为True就启动了删除已经sft过的数据的逻辑
MAX_GRAD_NORM=80.0

LR=5e-6
MODEL=Qwen2.5-Math-7B
EXP_NAME="${DATE}_${UNIFY_STRATEGY}-${OFFLINE_LOSS_TYPE}-${SFT_LOSS_COEF}_${MODEL}_gate@${SWITCH_GATE}_lr@${LR}_${TIME_TAG}"
MODEL_PATH=/fs-computility/prime/zuoyuxin/llms/$MODEL
DATA_DIR=$ROOT/data/

cd $ROOT/hpt/verl/
mkdir -p $ROOT/checkpoints/$EXP_NAME

TRAIN_FILE=${TRAIN_FILE:-"${DATA_DIR}/openr1.parquet"}
TEST_FILE=${TEST_FILE:-["${DATA_DIR}/AIME24/test.parquet","${DATA_DIR}/AMC23/test.parquet","${DATA_DIR}/MATH-500/test.parquet"]}

python3 -m verl.mix_src.main_mix_ppo \
    algorithm.adv_estimator=grpo \
    data.train_files=$TRAIN_FILE \
    data.val_files=$TEST_FILE \
    data.train_batch_size=128 \
    data.val_batch_size=512 \
    data.max_prompt_length=1024 \
    data.max_response_length=8192 \
    actor_rollout_ref.model.path=$MODEL_PATH \
    actor_rollout_ref.actor.optim.lr=$LR \
    actor_rollout_ref.model.use_remove_padding=True \
    actor_rollout_ref.actor.ppo_mini_batch_size=64 \
    actor_rollout_ref.actor.ppo_micro_batch_size=64 \
    actor_rollout_ref.actor.use_dynamic_bsz=True \
    actor_rollout_ref.actor.ppo_max_token_len_per_gpu=32768 \
    actor_rollout_ref.actor.kl_loss_coef=0.00 \
    actor_rollout_ref.actor.kl_loss_type=low_var_kl \
    actor_rollout_ref.actor.ulysses_sequence_parallel_size=1 \
    actor_rollout_ref.model.enable_gradient_checkpointing=True \
    actor_rollout_ref.actor.fsdp_config.param_offload=False \
    actor_rollout_ref.actor.fsdp_config.grad_offload=False \
    actor_rollout_ref.actor.fsdp_config.optimizer_offload=False \
    +actor_rollout_ref.actor.max_grad_norm=$MAX_GRAD_NORM \
    actor_rollout_ref.rollout.tensor_model_parallel_size=2 \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.temperature=1.0 \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.75 \
    actor_rollout_ref.rollout.n=8 \
    actor_rollout_ref.rollout.n_verify=8 \
    actor_rollout_ref.rollout.val_temperature=0.6 \
    +actor_rollout_ref.rollout.val_top_p=0.95 \
    actor_rollout_ref.rollout.n_val=8 \
    actor_rollout_ref.ref.fsdp_config.param_offload=True \
    actor_rollout_ref.rollout.max_prefix_len=8192 \
    algorithm.kl_ctrl.kl_coef=0.000 \
    actor_rollout_ref.actor.entropy_coeff=0.001 \
    trainer.critic_warmup=0 \
    trainer.logger=['console','swanlab'] \
    trainer.project_name="$WANDB_PROJECT" \
    trainer.experiment_name="$EXP_NAME" \
    +trainer.val_before_train=True \
    trainer.n_gpus_per_node=8 \
    trainer.nnodes=1 \
    trainer.save_freq=50 \
    trainer.test_freq=10 \
    trainer.unify_strategy="$UNIFY_STRATEGY" \
    trainer.switch_gate="$SWITCH_GATE" \
    trainer.switch_gate_off=$SWITCH_GATE_OFF \
    trainer.remove_sfted_data=$REMOVE_SFTED_DATA \
    actor_rollout_ref.actor.offline_loss_type="$OFFLINE_LOSS_TYPE" \
    actor_rollout_ref.actor.use_kl_loss=False \
    actor_rollout_ref.actor.use_sft_prefix_reward=False \
    actor_rollout_ref.rollout.prefix_share_across_samples=False \
    actor_rollout_ref.rollout.prefix_strategy=random \
    actor_rollout_ref.rollout.n_prefix=1 \
    actor_rollout_ref.rollout.min_prefix_ratio=1.0 \
    actor_rollout_ref.rollout.max_prefix_ratio=1.0 \
    actor_rollout_ref.rollout.prefix_reward_weight_alpha=1.0 \
    actor_rollout_ref.ref.use_ref=False \
    actor_rollout_ref.actor.sft_loss_coef=$SFT_LOSS_COEF \
    actor_rollout_ref.actor.off_policy_normalize=False \
    actor_rollout_ref.actor.off_policy_reshape="p_div_p_0.1" \
    actor_rollout_ref.actor.off_policy_loss_impl=token \
    algorithm.grpo_use_std=False \
    actor_rollout_ref.actor.loss_remove_token_mean=True \
    actor_rollout_ref.actor.loss_remove_clip=True \
    data.reward_impl_version=6 \
    trainer.max_optim_to_keep=2 \
    data.shuffle=True \
    trainer.default_hdfs_dir=null \
    trainer.total_training_steps=500 \
    trainer.default_local_dir=$ROOT/checkpoint/$EXP_NAME
