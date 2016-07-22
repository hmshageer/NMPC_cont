clear all; close all; clc;
warning('off','MATLAB:nargchk:deprecated');
%% Constants

n = 4;
m = 2;

%% Generate desired trajectory

T = 2*pi*20;
dt = 0.005;
t = (0:dt:T)';

x_d = sin(t/10);
y_d = sin(t/20);

v_xd = (1/10)*cos(t/10);
v_yd = (1/20)*cos(t/20);

v_d = sqrt(v_xd.^2 + v_yd.^2);
theta_d = atan2(v_yd,v_xd) + ((pi/6)-atan2(v_yd(1),v_xd(1)));

a_xd = -(1/100)*sin(t/10);
a_yd = -(1/400)*sin(t/20);

a_d = a_xd.*cos(theta_d) + a_yd.*sin(theta_d);
om_d = (a_yd.*cos(theta_d) - a_xd.*sin(theta_d))./v_d;

figure()
plot(x_d,y_d); grid on

% pause;

%% Construct constant CCM

lambda = 2.4;
r_vec = [2;2];
Ac = [];
Bc = [];
for i = 1:m
    Ac_i = [zeros(r_vec(i)-1,1), eye(r_vec(i)-1);
            zeros(1,r_vec(i))];
    Ac = blkdiag(Ac,Ac_i);
    
    Bc_i = [zeros(r_vec(i)-1,1);1];
    Bc = blkdiag(Bc,Bc_i);
end
B_perp = null(Bc');
cvx_begin sdp
    variable W_ccm(n,n) symmetric
    variables w_lower w_upper
    minimize (w_upper - w_lower)
    subject to
    W_ccm >= w_lower*eye(n);
    W_ccm <= w_upper*eye(n);
    w_lower >= 0.01;

    B_perp'*(Ac*W_ccm + W_ccm*Ac' + 2*lambda*W_ccm)*B_perp <= 0;
cvx_end

M_ccm = W_ccm\eye(n);

pause;

%% Setup aux controller and dynamics

eps_u = 0.2;
aux_prob = setup_opt_aux(m,eps_u);
geo_Ke = 1;

f = @(x) [x(3)*cos(x(4));
          x(3)*sin(x(4));
          0;
          0];
B = [zeros(2);eye(2)];
B_w = [zeros(2);eye(2)];
w_dist = 0.01*ones(2,1);

d_bar = norm(w_dist)*sqrt(max(eig(M_ccm)))/lambda;
euc_bound = d_bar/sqrt(min(eig(M_ccm)));

%% Setup geodesic mapping

phi = @(x) [x(1);
            x(3)*cos(x(4));
            x(2);
            x(3)*sin(x(4))];

phi_d = @(x) [1, zeros(1,3);
              0, 0, cos(x(4)), -x(3)*sin(x(4));
              0, 1, zeros(1,2);              
              0, 0, sin(x(4)),  x(3)*cos(x(4))];

M = @(x) M_ccm*phi_d(x);


%% Simulate

ode_options = odeset('RelTol', 1e-4, 'AbsTol', 1e-7);
start_p = [x_d(1); y_d(1); v_d(1); theta_d(1)] + [0.01;0.01;0;0.01].*randn(4,1);

T_steps = length(t)-1;

t_opt = cell(T_steps,1);

x_act = zeros(T_steps+1,n);
x_act(1,:) = start_p';

state = cell(T_steps,1);

ctrl = zeros(T_steps,m);
aux_ctrl = zeros(T_steps,m);

solved = ones(T_steps,1);

E = zeros(T_steps,1);

u_prev = zeros(m,1);

for i = 1:T_steps
    
%     fprintf('%d/%d \n',i, T_steps);
    
    x_nom = [x_d(i);y_d(i);v_d(i);theta_d(i)];
    u_nom = [a_d(i);om_d(i)];
    
    xi_nom = phi(x_nom);
    xi_act = phi(x_act(i,:)');
    
%     X_dot = geo_map(x_nom,x_act(i,:)',xi_nom,xi_act,phi_d,n);
    X_dot = kron(ones(1,2),xi_act-xi_nom);
    X = [x_nom, x_act(i,:)'];
    E(i) = (xi_act - xi_nom)'*M_ccm*(xi_act - xi_nom);
    
    [aux, solved(i)] = compute_opt_aux_FL(aux_prob,geo_Ke,...
                            X,X_dot,E(i),M,f,B,u_nom,u_prev,eps_u,lambda);
    aux_ctrl(i,:) = aux';
    
    ctrl(i,:) = u_nom' + aux';%zeros(1,m);
    u_prev = ctrl(i,:)';
    
%     [d_t,d_state] = ode113(@(t,d_state)ode_sim(t,d_state,ctrl(i,:)',f,B,B_w,w_dist),...
%         [t(i),t(i+1)],x_act(i,:),ode_options);
%     t_opt{i} = d_t;
%     state{i} = d_state;
%     x_act(i+1,:) = d_state(end,:);
    x_act(i+1,:) = x_act(i,:)+(f(x_act(i,:)') + B*ctrl(i,:)' + B_w*w_dist)'*dt;
    
end


%% Plot

close all


%Control effort
figure()
subplot(3,1,1)
plot(t,v_d,'r-','linewidth',2); hold on
plot(t,x_act(:,3),'b-','linewidth',2);
xlabel('Time [s]');
ylabel('v(t)'); 
grid on
legend('nominal','net');
set(findall(gcf,'type','text'),'FontSize',32);set(gca,'FontSize',32)

subplot(3,1,2)
plot(t(1:end-1),om_d(1:end-1),'r-','linewidth',2); hold on
plot(t(1:end-1),ctrl(:,2),'b-','linewidth',2);
xlabel('Time [s]');
ylabel('$\omega(t)$','interpreter','latex'); 
grid on
legend('nominal','net');
set(findall(gcf,'type','text'),'FontSize',32);set(gca,'FontSize',32)

subplot(3,1,3)
plot(t(1:end-1), aux_ctrl(:,1),'r-','linewidth',2); hold on
plot(t(1:end-1), aux_ctrl(:,2),'b-','linewidth',2);
xlabel('Time [s]'); 
ylabel('Auxiliary control'); 
grid on
legend('a','\omega');
set(findall(gcf,'type','text'),'FontSize',32);set(gca,'FontSize',32)


%Geodesic Energy
figure()
plot(t(1:end-1),E,'b-','linewidth',2); hold on
plot(t(1:end-1),(d_bar^2)*ones(T_steps,1),'r-','linewidth',2);
grid on
xlabel('Time [s]'); ylabel('Energy');

%Solve success
figure()
plot(t(1:end-1),solved(:,1),'go','markersize',10,'markerfacecolor','g');
grid on
xlabel('Time [s]');
set(findall(gcf,'type','text'),'FontSize',32);set(gca,'FontSize',32)

%Trajectory plot
figure()
plot(x_act(:,1),x_act(:,2),'b-','linewidth',2); hold on
plot(x_d,y_d,'r-','linewidth',2);
grid on
xlabel('x'); ylabel('y');
set(findall(gcf,'type','text'),'FontSize',32);set(gca,'FontSize',32)

%Trajectory errors
figure()
plot(t,x_d-x_act(:,1),'r-','linewidth',2); hold on
plot(t,y_d-x_act(:,2),'b-','linewidth',2);
grid on
xlabel('Time [s]');
ylabel('Traj errors');
legend('e_x','e_y');
set(findall(gcf,'type','text'),'FontSize',32);set(gca,'FontSize',32)


%%

save('car.mat','x_d','y_d','t','x_act');



