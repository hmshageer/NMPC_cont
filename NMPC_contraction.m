clear all; close all; clc;
warning('off','MATLAB:nargchk:deprecated');
         
%% Load non-linear system

load_FLR_config;

%% Setup Geodesic numerics

geodesic_N = 2;

setup_geodesic_MPC(n,geodesic_N,W_mat,dW_fnc,n_W); %initializes geodesic_MPC struct
global geodesic_MPC;

[geo_Prob,geo_Ke,T_e,T_dot_e,geo_Aeq] = ...
        setup_geodesic_calc(n,geodesic_N,W_mat,dW_fnc,n_W);
    
geo_warm = struct('sol',0,'result',[]);    

%% Setup MP numerics

% PVTOL:
% Tp = 28;
% dt = 0.001;
% N_mp = 120;

% FLR:
Tp = 5;
dt = 1/400;
N_mp = 50;


T_mpc = 0.5;
dt_sim = 1/200;
delta = 1;
N_mpc = 14;

% Setup motion planning problem
[MP_Prob,L_e_mp,MP_st] = setup_MP(n,m,...
    f,B,df, state_constr_low,ctrl_constr,...
    N_mp,Tp,dt,...
    P,alpha,d_bar^2,...
    x_eq,obs,'MP');

load MP_WARM_FLR.mat;
% mp_warm = struct('Tp',Tp,'shift',0,'sol',0,...
%                   's_t',MP_st,'state',[],'ctrl',[],'result',[]);

%% Test MP Solve
      
tic
[MP_state,MP_ctrl,converged_MP,mp_warm] = compute_MP(MP_Prob,...
    test_state,test_state,state_constr_low,ctrl_constr,x_eq,u_eq,...
    n,m,N_mp,L_e_mp,mp_warm);
toc
disp('MP:'); disp(converged_MP);

mp_warm.sol = 1;

%% Visualize

visualize_FLR;

%% Test Geodesic Numerics

tic
[~, ~,J_opt,converged_geo,geo_result,geo_Prob] = ...
    compute_geodesic_tom(geo_Prob,n,geodesic_N,...
            MP_state(1,:)',test_state,...
            T_e,T_dot_e,geo_Aeq,geo_warm);
toc;
disp('Geo dist: ');disp(converged_geo);
disp(sqrt(J_opt));
geo_Prob.CHECK = 1;
geo_warm.sol = 1;
geo_warm.result = geo_result;

tic
[X, X_dot,J_opt,converged_geo,geo_result_MPC,geo_Prob_MPC] = ...
    compute_geodesic_tom(geodesic_MPC.geo_Prob,n,geodesic_N,...
            MP_state(1,:)',test_state,...
            T_e,T_dot_e,geo_Aeq,geodesic_MPC.warm);
toc;
disp('MPC Geo dist: '); disp(converged_geo);
disp(sqrt(J_opt));
geo_Prob_MPC.CHECK = 1;
geodesic_MPC.geo_Prob = geo_Prob_MPC;
geodesic_MPC.warm.sol = 1;
geodesic_MPC.warm.result = geo_result_MPC;

figure(1)
subplot(2,1,1)
plot(X(1,:),X(3,:),'b-','linewidth',2);
subplot(2,1,2)
plot(X(2,:),X(4,:),'b-','linewidth',2);

% pause;

%% Setup MPC numerics

% [MPC_Prob,L_e,L_e_mpc,MPC_st] = setup_NMPC(n,m,...
%     f,B,df, state_constr_low,ctrl_constr,...
%     N_mpc,T_mpc,delta,dt,...
%     P,alpha,d_bar^2,...
%     x_eq,obs_mpc,'MPC');
% 
% load MPC_WARM_PVTOL.mat;

% mpc_warm = struct('Tp',T_mpc,'shift',0,'sol',0,'solve_t',0,...
%                   's_t',MPC_st,'state',[],'ctrl',[],'result',[]);

%% Test MPC solve
% tic
% [MPC_state,~,converged_MPC,mpc_warm,MPC_Prob] = compute_NMPC(MPC_Prob,...
%     test_state,MP_state(1,:)',state_constr_low,ctrl_constr,MP_state,MP_ctrl,...
%     n,m,N_mpc,L_e_mpc,mpc_warm,dt);
% toc
% disp('MPC:');disp(converged_MPC);
% 
% MPC_Prob.CHECK = 1;
% mpc_warm.sol = 1;
% 
% figure(1)
% plot(MPC_state(:,1),MPC_state(:,2),'r-','linewidth',2);
                
%% Setup Auxiliary controller
aux_Prob = setup_opt_aux(m);

tic
[ctrl_opt,converged_aux] = compute_opt_aux(aux_Prob,geo_Ke,X,X_dot,J_opt,...
                            W_mat,f,B,MP_ctrl(1,:)',lambda);
toc;
disp('opt_control:');disp(converged_aux);
disp(ctrl_opt);


%% Set up non-linear sim

ode_options = odeset('RelTol', 1e-6, 'AbsTol', 1e-9);

% dt_sim = 1/400;
t_end = Tp;
solve_t = (0:dt_sim:t_end)';
T_steps = length(solve_t)-1;

dt_MPC = delta;
solve_MPC = (0:dt_MPC:t_end)';
T_steps_MPC = length(solve_MPC)-1;

MPC_state = cell(T_steps_MPC,1);
MPC_ctrl = cell(T_steps_MPC,1);

accel_nom = zeros(T_steps,2);
w_dist = zeros(T_steps,2);

x_act = zeros(T_steps+1,n);
x_act(1,:) = test_state';

Geod = cell(T_steps,1);

Aux_ctrl = zeros(T_steps,m);
True_ctrl = zeros((t_end/dt)+1,m);
Nom_ctrl = zeros((t_end/dt)+1,m);

ctrl_solve_time = zeros(T_steps,3);
ctrl_solve_time(:,1) = NaN;

opt_solved = NaN(T_steps,3);

geo_energy = zeros(T_steps,2);
geo_energy(:,2) = NaN;

state_0 = test_state;
state_0_MPC = MP_state(1,:)';

i_mpc = 0;

      
%% Simulate

track_traj = 1;

if (~track_traj)
    for i = 1:T_steps
        
        %First Solve MPC
        if (mod(solve_t(i),delta)==0)
            
            fprintf('%d/%d:',i,T_steps);
            
            [~, ~,J_opt,~,~,geo_Prob] = compute_geodesic_tom(geo_Prob,...
                n,geodesic_N,state_0_MPC,state_0,T_e,T_dot_e,geo_Aeq,geo_warm);
            geo_energy(i,1) = J_opt;
            
            tic
            [MPC_x,MPC_u,opt_solved(i,1),mpc_warm,MPC_Prob] = ...
                compute_NMPC(MPC_Prob,state_0,state_0_MPC,state_constr_low,ctrl_constr,MP_state,MP_ctrl,...
                n,m,N_mpc,L_e_mpc,mpc_warm,dt);
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
                x_nom',state_0,T_e,T_dot_e,geo_Aeq,geo_warm);
            
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
            n,geodesic_N,x_nom',state_0,T_e,T_dot_e,geo_Aeq,geo_warm);
        ctrl_solve_time(i,2) = toc;
        
        Geod{i} = X';
        geo_energy(i,1) = J_opt;
        geo_warm.result = geo_result;
        
        tic
        [Aux_ctrl(i,:),opt_solved(i,3)] = compute_opt_aux(aux_Prob,geo_Ke,X,X_dot,J_opt,...
            W_mat,f,B,u_nom(1,:)',lambda);
        ctrl_solve_time(i,3) = toc;
        
        True_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:) = u_nom+kron(ones((dt_sim/dt)+1,1),Aux_ctrl(i,:));
        Nom_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:) = u_nom;
        
        %Simulate Optimal
        w_dist(i,:) = w_max*[cos(x_act(i,3));
            -sin(x_act(i,3))]';
        
        %     dist_dir = (X_dot(:,geo_Ke+1))'*(W_mat(state_0)\eye(n))*B_w;
        %     w_dist(i,:) = w_max*(dist_dir/norm(dist_dir));
        %     w_dist = zeros(2,1);
        
        [d_t,d_state] = ode113(@(t,d_state)ode_sim(t,d_state,[solve_t(i):dt:solve_t(i+1)]',u_nom,Aux_ctrl(i,:),...
            f,B,B_w,w_dist(i,:)'),[solve_t(i),solve_t(i+1)],state_0,ode_options);
        
        state_0 = d_state(end,:)';
        x_act(i+1,:) = state_0';
    end
else
    for i = 1:T_steps
        
        x_nom = MP_state(1+(i-1)*(dt_sim/dt),:);
        u_nom = MP_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:);
        
        %Optimal Control
        tic
        [X, X_dot,J_opt,opt_solved(i,2),geo_result,geo_Prob] = compute_geodesic_tom(geo_Prob,...
            n,geodesic_N,x_nom',state_0,T_e,T_dot_e,geo_Aeq,geo_warm);
        ctrl_solve_time(i,2) = toc;
        
        Geod{i} = X';
        geo_energy(i,1) = J_opt;
        geo_warm.result = geo_result;
        
        tic
        [Aux_ctrl(i,:),opt_solved(i,3)] = compute_opt_aux(aux_Prob,geo_Ke,X,X_dot,J_opt,...
            W_mat,f,B,u_nom(1,:)',lambda);
        ctrl_solve_time(i,3) = toc;
        
        True_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:) = u_nom+kron(ones((dt_sim/dt)+1,1),Aux_ctrl(i,:));
        Nom_ctrl(1+(i-1)*(dt_sim/dt):1+i*(dt_sim/dt),:) = u_nom;
        
        %Simulate Optimal
        dist_dir = (X_dot(:,geo_Ke+1))'*(W_mat(state_0)\eye(n))*B_w;
        w_dist(i,:) = w_max*(dist_dir/norm(dist_dir));
        
        [d_t,d_state] = ode113(@(t,d_state)ode_sim(t,d_state,[solve_t(i):dt:solve_t(i+1)]',u_nom,Aux_ctrl(i,:),...
            f,B,B_w,w_dist(i,:)'),[solve_t(i),solve_t(i+1)],state_0,ode_options);
        
        state_0 = d_state(end,:)';
        x_act(i+1,:) = state_0';
    end
end

%% Plots

plot_FLR;

%% Evaluate cost

%Control cost weighting
R = eye(m);

J_cost = zeros((t_end/dt)+1,1);
for i = 1:(t_end/dt)+1
    J_cost(i) = True_ctrl(i,:)*R*True_ctrl(i,:)';
end

disp('NET COST:'); disp(trapz([0:dt:t_end],J_cost));

%Evaluate nominal cost
J_nom_mp = zeros((t_end/dt)+1,1);
for i = 1:(t_end/dt)+1
    J_nom_mp(i) = MP_ctrl(i,:)*R*MP_ctrl(i,:)';
end
disp('NOMINAL MP COST:'); disp(trapz([0:dt:t_end],J_nom_mp));

figure()
plot([0:dt:t_end],cumtrapz([0:dt:t_end],J_nom_mp),'r-','linewidth',2);
grid on
xlabel('Time [s]'); grid on;
hold on

J_nom_mpc = zeros((t_end/dt)+1,1);
for i = 1:(t_end/dt)+1
    J_nom_mpc(i) = Nom_ctrl(i,:)*R*Nom_ctrl(i,:)';
end
disp('NOMINAL MPC COST:'); disp(trapz([0:dt:t_end],J_nom_mpc));
plot([0:dt:t_end],cumtrapz([0:dt:t_end],J_nom_mpc),'b-','linewidth',2);

