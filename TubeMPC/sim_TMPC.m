clear all; close all; clc;
warning('off','MATLAB:nargchk:deprecated');
         
%% Load non-linear system

load_TMPC_config;

%% Setup Geodesic numerics

geodesic_N = 1;

setup_geodesic_MPC(n,geodesic_N,W_fnc,dW_fnc,n_W); %initializes geodesic_MPC struct
global geodesic_MPC;

[geo_Prob,geo_Ke,T_e,T_dot_e,geo_Aeq] = ...
        setup_geodesic_calc(n,geodesic_N,W_fnc,dW_fnc,n_W);
    
geo_solver = 'npsol';    
    
geo_warm = struct('sol',0,'result',[]);    

%% Setup MPC numerics

T_mpc = 1.5;
delta = 0.1;
dt = 0.005;

N_mpc = 24;
dt_sim = dt;

% Setup MPC problem (using MP setup rather than NMPC)
[MPC_Prob,L_e_mpc,MPC_st] = setup_MP(n,m,...
    f,B,df, state_constr,ctrl_constr,...
    N_mpc,T_mpc,dt,...
    P,alpha,(d_bar)^2,...
    x_eq,obs,Q,R,'MPC');

%load MPC_WARM_TMPC.mat;
 mpc_warm = struct('Tp',T_mpc,'shift',0,'sol',0,'solve_t',0,...
                   's_t',MPC_st,'state',[],'ctrl',[],'result',[]);

%% Test MPC Solve
      
tic
[MP_state,MP_ctrl,converged_MPC,mpc_warm] = compute_MP(MPC_Prob,...
    test_state,test_state,state_constr,ctrl_constr,x_eq,u_eq,...
    n,m,N_mpc,L_e_mpc,mpc_warm);
toc
disp('MPC:'); disp(converged_MPC);

MPC_Prob = ProbCheck(MPC_Prob,'snopt');
mpc_warm.sol = 1;
save('MPC_WARM_TMPC.mat','mpc_warm');

%% Visualize

visualize_TMPC;

%% Test Geodesic Numerics

tic
[X, X_dot,J_opt,converged_geo,geo_result,geo_Prob] = ...
    compute_geodesic_tom(geo_Prob,n,geodesic_N,...
            MP_state(1,:)',test_state,...
            T_e,T_dot_e,geo_Aeq,geo_warm,geo_solver);
toc;
disp('Geo dist: ');disp(converged_geo);
disp(sqrt(J_opt));
geo_Prob.CHECK = 1;
geo_warm.sol = 1;
geo_warm.result = geo_result;

tic
[~, ~,J_opt,converged_geo,geo_result_MPC,geo_Prob_MPC] = ...
    compute_geodesic_tom(geodesic_MPC.geo_Prob,n,geodesic_N,...
            MP_state(1,:)',test_state,...
            T_e,T_dot_e,geo_Aeq,geodesic_MPC.warm,'npsol');
toc;
disp('MPC Geo dist: '); disp(converged_geo);
disp(sqrt(J_opt));
geo_Prob_MPC.CHECK = 1;
geodesic_MPC.geo_Prob = geo_Prob_MPC;
geodesic_MPC.warm.sol = 1;
geodesic_MPC.warm.result = geo_result_MPC;
                
%% Setup Auxiliary controller

tic
[ctrl_opt,converged_aux] = compute_opt_aux(geo_Ke,X,X_dot,J_opt,...
                            W_fnc,f,B,MP_ctrl(1,:)',lambda);
toc;
disp('opt_control:');disp(converged_aux);
disp(ctrl_opt);


%% Set up non-linear sim

ode_options = odeset('RelTol', 1e-6, 'AbsTol', 1e-9);

t_end = 2*T_mpc;
solve_t = (0:dt_sim:t_end)';
T_steps = length(solve_t)-1;

dt_MPC = delta;
solve_MPC = (0:dt_MPC:t_end)';
T_steps_MPC = length(solve_MPC)-1;

MPC_state = cell(T_steps_MPC,1);
MPC_ctrl = cell(T_steps_MPC,1);

w_dist = zeros(T_steps,1);

x_act = zeros(T_steps+1,n);

Geod = cell(T_steps,1);

Aux_ctrl = zeros(T_steps,m);
True_ctrl = zeros((t_end/dt)+1,m);
Nom_ctrl = zeros((t_end/dt)+1,m);

ctrl_solve_time = zeros(T_steps,3);
ctrl_solve_time(:,1) = NaN;

opt_solved = NaN(T_steps,3);

geo_energy = zeros(T_steps,2);
geo_energy(:,2) = NaN;

x_act(1,:) = test_state';
state = test_state;
state_0_MPC = MP_state(1,:)';

i_mpc = 0;
      
%% Simulate
disp('Ready to Simulate');
keyboard;

for i = 1:T_steps
    
    %First Solve MPC
    if (mod(solve_t(i),delta)==0)
        
        fprintf('%d/%d:',i,T_steps);
        
        [~, ~,J_opt,~,~,geo_Prob] = compute_geodesic_tom(geo_Prob,...
            n,geodesic_N,state_0_MPC,state,T_e,T_dot_e,geo_Aeq,geo_warm,geo_solver);
        geo_energy(i,1) = J_opt;

        tic
        [MPC_x,MPC_u,opt_solved(i,1),mpc_warm] = compute_MP(MPC_Prob,state,state_0_MPC,state_constr,ctrl_constr,x_eq,u_eq,...
                                                        n,m,N_mpc,L_e_mpc,mpc_warm);
        ctrl_solve_time(i,1) = toc;
        
        fprintf('%d, %.2f \n', opt_solved(i,1),ctrl_solve_time(i,1));
        
        mpc_warm.solve_t = solve_t(i);
        mpc_warm.shift = delta;
        mpc_warm.sol = 1;
        
        i_mpc = i_mpc + 1;
        
        MPC_state{i_mpc} = MPC_x;
        MPC_ctrl{i_mpc} = MPC_u;
        
        x_nom = MPC_state{i_mpc}(1,:);
        u_nom = MPC_ctrl{i_mpc}(1:round(dt_sim/dt)+1,:);
        
        [~, ~,J_opt,~,geo_result,geo_Prob] = compute_geodesic_tom(geo_Prob,n,geodesic_N,...
            x_nom',state,T_e,T_dot_e,geo_Aeq,geo_warm,geo_solver);
        
        geo_energy(i,2) = J_opt;
        geo_warm.result = geo_result;
        
        %update starting state for next MPC problem
        state_0_MPC = MPC_state{i_mpc}(round(delta/dt)+1,:)';
    else
        i_mpc_use = round((mod(solve_t(i),delta))/dt)+1;
        x_nom = MPC_state{i_mpc}(i_mpc_use,:);
        u_nom = MPC_ctrl{i_mpc}(i_mpc_use:i_mpc_use+round(dt_sim/dt),:);
    end
    
    %Optimal Control
    tic
    [X, X_dot,J_opt,opt_solved(i,2),geo_result,geo_Prob] = compute_geodesic_tom(geo_Prob,...
        n,geodesic_N,x_nom',state,T_e,T_dot_e,geo_Aeq,geo_warm,geo_solver);
    ctrl_solve_time(i,2) = toc;
    
    Geod{i} = X';
    geo_energy(i,1) = J_opt;
    geo_warm.result = geo_result;
    
    tic
    [Aux_ctrl(i,:),opt_solved(i,3)] = compute_opt_aux(geo_Ke,X,X_dot,J_opt,...
        W_fnc,f,B,u_nom(1,:)',lambda);
    ctrl_solve_time(i,3) = toc;
    
    True_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:) = u_nom+kron(ones((dt_sim/dt)+1,1),Aux_ctrl(i,:));
    Nom_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:) = u_nom;
    
    %Simulate Optimal
    w_dist(i,:) = w_max;
    
    [d_t,d_state] = ode113(@(t,d_state)ode_sim(t,d_state,[solve_t(i):dt:solve_t(i+1)]',u_nom,Aux_ctrl(i,:),...
        f,B,B_w,w_dist(i,:)'),[solve_t(i),solve_t(i+1)],state,ode_options);
    
    state = d_state(end,:)';
    x_act(i+1,:) = state';
end


%% Plots

close all;
plot_TMPC;


