function J = NMPC_grad(xu,n,N,Q_bar,R_bar,P,Tp)

    J = (Tp/2)*xu(1:n*(N+1))'*Q_bar*xu(1:n*(N+1)) + ...
        (Tp/2)*xu(n*(N+1)+1:end)'*R_bar*xu(n*(N+1)+1:end) + ...
               xu(n*N+1:n*(N+1))'*P*xu(n*N+1:n*(N+1));
end